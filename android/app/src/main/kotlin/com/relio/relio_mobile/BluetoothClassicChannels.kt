package com.relio.relio_mobile

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.zip.CRC32

/**
 * Native secure RFCOMM bridge used only by the DEV/QA compatibility path.
 * เปิด listener หลังผ่าน permission check และรายงานผลกลับ Flutter ผ่าน channel
 */
class BluetoothClassicChannels(private val activity: Activity) : EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "relio/bluetooth_classic"
        private const val EVENT_CHANNEL = "relio/bluetooth_classic/events"
        private const val MAGIC = 0x524c
        private const val VERSION = 1
        private const val TYPE_BYTES = 1
        private const val TYPE_FILE_CHUNK = 2
        private const val MAX_FRAME_PAYLOAD = 2 * 1024 * 1024
        private const val FILE_CHUNK_SIZE = 32 * 1024
        private const val CONNECT_TIMEOUT_MS = 15_000
        private val SERVICE_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private data class Connection(
        val endpointId: String,
        val name: String,
        val socket: BluetoothSocket,
        var accepted: Boolean = false,
        var readerStarted: Boolean = false,
    ) {
        val writeLock = Any()
    }

    private class IncomingFile(
        val transferId: String,
        val totalBytes: Long,
        val totalChunks: Int,
        val file: File,
        val raf: RandomAccessFile,
        val receivedChunks: MutableSet<Int> = mutableSetOf(),
    )

    private val handler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val bluetoothManager = activity.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? get() = bluetoothManager?.adapter
    private val connections = ConcurrentHashMap<String, Connection>()
    private val pendingConnections = ConcurrentHashMap<String, Connection>()
    private val connectingPeers = ConcurrentHashMap.newKeySet<String>()
    private val incomingFiles = ConcurrentHashMap<String, IncomingFile>()
    private var serverSocket: BluetoothServerSocket? = null
    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private var discovering = false
    private var advertising = false
    private var advertisingStarting = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val device = intent?.getParcelableExtraCompat<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                ?: return
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> publishPeer(device)
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    discovering = false
                    publishDiagnostic("bluetooth_classic_discovery_finished")
                }
            }
        }
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(::handleCall)
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startAdvertising" -> {
                    startAdvertising()
                    result.success(null)
                }
                "stopAdvertising" -> {
                    stopAdvertising()
                    result.success(null)
                }
                "startDiscovery" -> {
                    startDiscovery()
                    result.success(null)
                }
                "stopDiscovery" -> {
                    stopDiscovery()
                    result.success(null)
                }
                "reset", "dispose" -> {
                    closeAll()
                    result.success(null)
                }
                "acceptConnection" -> {
                    val peerId = call.argument<String>("peerId") ?: error("missing peer")
                    acceptConnection(peerId)
                    result.success(null)
                }
                "rejectConnection" -> {
                    val peerId = call.argument<String>("peerId") ?: error("missing peer")
                    pendingConnections.remove(peerId)?.close()
                    emitConnection(peerId, "disconnected", incoming = true)
                    result.success(null)
                }
                "requestConnection" -> {
                    val peerId = call.argument<String>("peerId") ?: error("missing peer")
                    requestConnection(peerId)
                    result.success(null)
                }
                "disconnect" -> {
                    val peerId = call.argument<String>("peerId") ?: error("missing peer")
                    connections.remove(peerId)?.close()
                    pendingConnections.remove(peerId)?.close()
                    emitConnection(peerId, "disconnected")
                    result.success(null)
                }
                "sendBytes" -> {
                    val peerId = call.argument<String>("peerId") ?: error("missing peer")
                    val bytes = call.argument<ByteArray>("bytes") ?: error("missing bytes")
                    sendFrame(peerId, TYPE_BYTES, bytes)
                    result.success(null)
                }
                "sendFile" -> {
                    val peerId = call.argument<String>("peerId") ?: error("missing peer")
                    val path = call.argument<String>("path") ?: error("missing path")
                    sendFile(peerId, path, result)
                }
                "snapshot" -> result.success(snapshot())
                "bondedDevices" -> result.success(bondedDevices())
                else -> result.notImplemented()
            }
        } catch (_: SecurityException) {
            result.error("bluetooth_permission", "Bluetooth permission is unavailable", null)
        } catch (_: Throwable) {
            result.error("bluetooth_classic_error", "Bluetooth compatibility operation failed", null)
        }
    }

    @Synchronized
    private fun startAdvertising() {
        requireBluetoothPermission()
        if (advertising || advertisingStarting) return
        advertisingStarting = true
        try {
        val currentAdapter = adapter ?: error("Bluetooth unavailable")
        val socket = currentAdapter.listenUsingRfcommWithServiceRecord("RELIO", SERVICE_UUID)
        serverSocket = socket
        advertising = true
        executor.execute {
            while (advertising) {
                try {
                    val accepted = socket.accept()
                    registerIncoming(accepted)
                } catch (_: IOException) {
                    if (advertising) publishDiagnostic("bluetooth_classic_accept_failed")
                    break
                } catch (_: SecurityException) {
                    break
                }
            }
        }
        publishDiagnostic("bluetooth_classic_server_started")
        } finally {
            advertisingStarting = false
        }
    }

    private fun stopAdvertising() {
        advertising = false
        try { serverSocket?.close() } catch (_: IOException) { }
        serverSocket = null
    }

    private fun startDiscovery() {
        requireBluetoothPermission(scan = true)
        if (discovering) return
        registerReceiver()
        adapter?.bondedDevices?.forEach(::publishPeer)
        adapter?.cancelDiscovery()
        discovering = adapter?.startDiscovery() == true
        publishDiagnostic(if (discovering) "bluetooth_classic_discovery_started" else "bluetooth_classic_discovery_unavailable")
    }

    private fun stopDiscovery() {
        discovering = false
        try { adapter?.cancelDiscovery() } catch (_: SecurityException) { }
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        ContextCompat.registerReceiver(activity, receiver, filter, ContextCompat.RECEIVER_EXPORTED)
        receiverRegistered = true
    }

    private fun registerIncoming(socket: BluetoothSocket) {
        val device = socket.remoteDevice
        val endpointId = endpointId(device)
        if (connections.containsKey(endpointId)) {
            socket.close()
            return
        }
        val connection = Connection(endpointId, safeDeviceName(device), socket)
        if (pendingConnections.putIfAbsent(endpointId, connection) != null) {
            socket.close()
            return
        }
        publishPeer(device)
        emitConnection(endpointId, "incomingRequest", incoming = true, name = connection.name)
    }

    private fun acceptConnection(endpointId: String) {
        val pending = pendingConnections.remove(endpointId) ?: connections[endpointId]
            ?: error("Bluetooth connection is no longer pending")
        pending.accepted = true
        connections[endpointId] = pending
        emitConnection(endpointId, "connected", name = pending.name)
        startReader(pending)
    }

    private fun requestConnection(endpointId: String) {
        val address = addressFromEndpoint(endpointId) ?: error("invalid Bluetooth peer")
        if (connections.containsKey(endpointId) || !connectingPeers.add(endpointId)) return
        emitConnection(endpointId, "connecting")
        executor.execute {
            try {
                val currentAdapter = adapter ?: error("Bluetooth unavailable")
                val device = currentAdapter.bondedDevices.firstOrNull {
                    it.address.equals(address, ignoreCase = true)
                } ?: error("Bluetooth peer is not bonded")
                currentAdapter.cancelDiscovery()
                val socket = device.createRfcommSocketToServiceRecord(SERVICE_UUID)
                socket.connectWithTimeout()
                val connection = Connection(endpointId, safeDeviceName(device), socket, accepted = true)
                val existing = connections.putIfAbsent(endpointId, connection)
                if (existing != null) {
                    socket.close()
                } else {
                    emitConnection(endpointId, "connected", name = connection.name)
                    startReader(connection)
                }
            } catch (error: Throwable) {
                val detail = "RFCOMM_CONNECT_FAILED:${error.javaClass.simpleName}:${error.message.orEmpty().take(120)}"
                publishDiagnostic("bluetooth_classic_connect_failed", mapOf("error" to detail))
                emitConnection(endpointId, "failed", error = detail)
            } finally {
                connectingPeers.remove(endpointId)
            }
        }
    }

    private fun BluetoothSocket.connectWithTimeout() {
        val task = executor.submit { connect() }
        try {
            task.get(CONNECT_TIMEOUT_MS.toLong(), java.util.concurrent.TimeUnit.MILLISECONDS)
        } finally {
            if (!task.isDone) task.cancel(true)
        }
    }

    private fun startReader(connection: Connection) {
        if (connection.readerStarted) return
        connection.readerStarted = true
        executor.execute {
            try {
                val input = DataInputStream(connection.socket.inputStream.buffered())
                while (connections[connection.endpointId] === connection) {
                    val magic = input.readUnsignedShort()
                    val version = input.readUnsignedByte()
                    val type = input.readUnsignedByte()
                    val length = input.readInt()
                    val checksum = input.readInt()
                    if (magic != MAGIC || version != VERSION || length < 0 || length > MAX_FRAME_PAYLOAD) {
                        throw IOException("invalid frame")
                    }
                    val payload = ByteArray(length)
                    input.readFully(payload)
                    if (crc32(payload) != checksum) throw IOException("invalid checksum")
                    when (type) {
                        TYPE_BYTES -> emitBytes(connection.endpointId, payload)
                        TYPE_FILE_CHUNK -> receiveFileChunk(connection.endpointId, payload)
                        else -> throw IOException("unsupported frame")
                    }
                }
            } catch (_: Throwable) {
                // Disconnect is reported once below; malformed data never reaches RELIO.
            } finally {
                if (connections.remove(connection.endpointId, connection)) {
                    try { connection.socket.close() } catch (_: IOException) { }
                    emitConnection(connection.endpointId, "disconnected", name = connection.name)
                }
            }
        }
    }

    private fun sendFrame(endpointId: String, type: Int, payload: ByteArray) {
        val connection = connections[endpointId] ?: error("Bluetooth peer is not connected")
        require(payload.size <= MAX_FRAME_PAYLOAD)
        synchronized(connection.writeLock) {
            val output = DataOutputStream(connection.socket.outputStream.buffered())
            output.writeShort(MAGIC)
            output.writeByte(VERSION)
            output.writeByte(type)
            output.writeInt(payload.size)
            output.writeInt(crc32(payload))
            output.write(payload)
            output.flush()
        }
    }

    private fun sendFile(endpointId: String, path: String, result: MethodChannel.Result) {
        val source = File(path)
        require(source.isFile)
        val transferId = UUID.randomUUID().toString()
        executor.execute {
            try {
                val totalBytes = source.length()
                val totalChunks = maxOf(1, ((totalBytes + FILE_CHUNK_SIZE - 1) / FILE_CHUNK_SIZE).toInt())
                emitTransfer(endpointId, transferId, "started", 0, totalBytes)
                source.inputStream().use { input ->
                    var index = 0
                    var sent = 0L
                    do {
                        val chunk = input.readNBytes(FILE_CHUNK_SIZE)
                        val metadata = ByteArrayOutputStream()
                        DataOutputStream(metadata).use { output ->
                            val id = transferId.toByteArray(Charsets.UTF_8)
                            output.writeShort(id.size)
                            output.write(id)
                            output.writeInt(index)
                            output.writeInt(totalChunks)
                            output.writeLong(totalBytes)
                            output.writeInt(chunk.size)
                            output.write(chunk)
                        }
                        sendFrame(endpointId, TYPE_FILE_CHUNK, metadata.toByteArray())
                        sent += chunk.size
                        emitTransfer(endpointId, transferId, "inProgress", sent, totalBytes)
                        index++
                    } while (index < totalChunks)
                }
                emitTransfer(endpointId, transferId, "success", totalBytes, totalBytes)
                handler.post { result.success(transferId) }
            } catch (_: Throwable) {
                emitTransfer(endpointId, transferId, "failure", 0, source.length())
                handler.post { result.error("bluetooth_file_failed", "Bluetooth file transfer failed", null) }
            }
        }
    }

    private fun receiveFileChunk(endpointId: String, payload: ByteArray) {
        try {
            val input = DataInputStream(ByteArrayInputStream(payload))
            val idLength = input.readUnsignedShort()
            require(idLength in 1..128)
            val transferId = input.readNBytes(idLength).toString(Charsets.UTF_8)
            val index = input.readInt()
            val totalChunks = input.readInt()
            val totalBytes = input.readLong()
            val chunkLength = input.readInt()
            require(index >= 0 && totalChunks > 0 && index < totalChunks)
            require(totalBytes in 0..(512L * 1024 * 1024) && chunkLength in 0..FILE_CHUNK_SIZE)
            val chunk = input.readNBytes(chunkLength)
            require(chunk.size == chunkLength)
            val transfer = incomingFiles.computeIfAbsent(transferId) {
                val file = File.createTempFile("relio-bt-", ".media", activity.cacheDir)
                val raf = RandomAccessFile(file, "rw")
                raf.setLength(totalBytes)
                IncomingFile(transferId, totalBytes, totalChunks, file, raf)
            }
            if (transfer.totalBytes != totalBytes || transfer.totalChunks != totalChunks) throw IOException("file metadata mismatch")
            if (transfer.receivedChunks.add(index)) {
                transfer.raf.seek(index.toLong() * FILE_CHUNK_SIZE)
                transfer.raf.write(chunk)
            }
            emitTransfer(endpointId, transferId, "inProgress", transfer.receivedChunks.size.toLong(), totalChunks.toLong())
            if (transfer.receivedChunks.size == totalChunks) {
                transfer.raf.close()
                incomingFiles.remove(transferId)
                emitTransfer(endpointId, transferId, "success", totalBytes, totalBytes)
                emit(mapOf("kind" to "file", "peerId" to endpointId, "payloadId" to transferId, "path" to transfer.file.absolutePath))
            }
        } catch (_: Throwable) {
            publishDiagnostic("bluetooth_classic_file_frame_rejected")
        }
    }

    private fun emitBytes(endpointId: String, bytes: ByteArray) = emit(
        mapOf("kind" to "bytes", "peerId" to endpointId, "bytes" to bytes),
    )

    private fun emitTransfer(endpointId: String, id: String, status: String, transferred: Long, total: Long) = emit(
        mapOf("kind" to "transfer", "peerId" to endpointId, "payloadId" to id, "status" to status, "bytesTransferred" to transferred, "totalBytes" to total),
    )

    private fun emitConnection(endpointId: String, state: String, error: String? = null, incoming: Boolean = false, name: String = "Bluetooth • RELIO") {
        val values = mutableMapOf<String, Any?>("kind" to "connection", "peerId" to endpointId, "state" to state, "incoming" to incoming, "name" to name)
        if (error != null) values["error"] = error
        emit(values)
    }

    private fun publishPeer(device: BluetoothDevice) {
        val id = endpointId(device)
        emit(mapOf("kind" to "peerFound", "peerId" to id, "name" to safeDeviceName(device)))
    }

    private fun publishDiagnostic(name: String, fields: Map<String, Any?> = emptyMap()) = emit(
        mapOf(
            "kind" to "diagnostic",
            "name" to name,
            "fields" to mapOf("transport" to "BLUETOOTH_CLASSIC_RFCOMM") + fields,
        ),
    )

    private fun emit(value: Map<String, Any?>) {
        handler.post { eventSink?.success(value) }
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "transport" to "BLUETOOTH_CLASSIC_RFCOMM",
        "bluetoothEnabled" to try { adapter?.isEnabled } catch (_: SecurityException) { null },
        "bondedCount" to try { adapter?.bondedDevices?.size ?: 0 } catch (_: SecurityException) { 0 },
        "activeConnections" to connections.size,
        "pendingConnections" to pendingConnections.size,
        "connectingPeers" to connectingPeers.size,
        "discovering" to discovering,
        "advertising" to advertising,
    )

    private fun bondedDevices(): List<Map<String, String>> {
        requireBluetoothPermission()
        val devices = adapter?.bondedDevices.orEmpty().sortedBy { it.address }
        devices.forEach(::publishPeer)
        return devices.map { device ->
            mapOf(
                "address" to device.address.uppercase(),
                "name" to safeDeviceName(device),
                "bondState" to when (device.bondState) {
                    BluetoothDevice.BOND_BONDED -> "BONDED"
                    BluetoothDevice.BOND_BONDING -> "BONDING"
                    else -> "NONE"
                },
            )
        }
    }

    private fun closeAll() {
        stopDiscovery()
        stopAdvertising()
        connections.values.forEach { it.close() }
        pendingConnections.values.forEach { it.close() }
        connections.clear()
        pendingConnections.clear()
        incomingFiles.values.forEach {
            try { it.raf.close() } catch (_: IOException) { }
            it.file.delete()
        }
        incomingFiles.clear()
        if (receiverRegistered) {
            try { activity.unregisterReceiver(receiver) } catch (_: IllegalArgumentException) { }
            receiverRegistered = false
        }
    }

    private fun Connection.close() {
        try { socket.close() } catch (_: IOException) { }
    }

    private fun requireBluetoothPermission(scan: Boolean = false) {
        if (Build.VERSION.SDK_INT >= 31 && ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("Bluetooth connect permission missing")
        }
        if (scan && Build.VERSION.SDK_INT >= 31 && ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("Bluetooth scan permission missing")
        }
    }

    private fun endpointId(device: BluetoothDevice): String = "classic:${device.address.uppercase()}"

    private fun addressFromEndpoint(endpointId: String): String? = endpointId.removePrefix("classic:").takeIf { it.matches(Regex("[0-9A-F]{2}(:[0-9A-F]{2}){5}")) }

    private fun safeDeviceName(device: BluetoothDevice): String = try {
        device.name?.take(80)?.ifBlank { "Bluetooth • RELIO" } ?: "Bluetooth • RELIO"
    } catch (_: SecurityException) { "Bluetooth • RELIO" }

    private fun crc32(bytes: ByteArray): Int {
        val crc = CRC32()
        crc.update(bytes)
        return crc.value.toInt()
    }

    private fun <T> Intent.getParcelableExtraCompat(name: String): T? = if (Build.VERSION.SDK_INT >= 33) {
        getParcelableExtra(name, BluetoothDevice::class.java) as? T
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(name) as? T
    }
}
