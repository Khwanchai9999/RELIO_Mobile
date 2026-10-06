package com.pkmnapps.nearby_connections;

import android.app.Activity;
import android.content.pm.PackageInfo;
import android.util.Log;
import android.os.Build.VERSION;
import android.os.Build.VERSION_CODES;
import android.os.SystemClock;
import android.net.Uri;

import androidx.annotation.NonNull;

import com.google.android.gms.nearby.Nearby;
import com.google.android.gms.nearby.connection.AdvertisingOptions;
import com.google.android.gms.nearby.connection.ConnectionInfo;
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback;
import com.google.android.gms.nearby.connection.ConnectionResolution;
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes;
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo;
import com.google.android.gms.nearby.connection.DiscoveryOptions;
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback;
import com.google.android.gms.nearby.connection.Payload;
import com.google.android.gms.nearby.connection.PayloadCallback;
import com.google.android.gms.nearby.connection.PayloadTransferUpdate;
import com.google.android.gms.nearby.connection.Strategy;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.FileOutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.EventChannel;

/**
 * NearbyConnectionsPlugin
 */
public class NearbyConnectionsPlugin implements MethodCallHandler, FlutterPlugin, ActivityAware {
	private Activity activity;
	private static final String SERVICE_ID = "com.pkmnapps.nearby_connections";
	private static MethodChannel channel;
	private static EventChannel eventChannel;
	private static EventChannel.EventSink eventSink;
	private final Map<String, Long> connectionStartedAt = new ConcurrentHashMap<>();
	private final Map<String, String> connectionTraceIds = new ConcurrentHashMap<>();
	private final Map<String, String> connectionOperations = new ConcurrentHashMap<>();
	private final Map<String, Boolean> incomingConnections = new ConcurrentHashMap<>();
	private volatile int advertisingStrategy = 0;
	private volatile int discoveryStrategy = 0;
	private NearbyConnectionsPlugin(Activity activity) {
		this.activity = activity;
	}

	public NearbyConnectionsPlugin() {
	}

	@Override
	public void onMethodCall(MethodCall call, final Result result) {

		switch (call.method) {
			case "getNearbyDiagnostics":
				result.success(getNearbyDiagnostics());
				break;
			case "copyFileAndDeleteOriginal":
				Log.d("nearby_connections", "copyFileAndDeleteOriginal");
				String sourceUri = (String) call.argument("sourceUri");
				String destinationFilepath = (String) call.argument("destinationFilepath");

				try {
					// Copy the file to a new location.
					Uri uri = Uri.parse(sourceUri);
					InputStream in = activity.getContentResolver().openInputStream(uri);
					copyStream(in, new FileOutputStream(new File(destinationFilepath)));
					// Delete the original file.
					activity.getContentResolver().delete(uri, null, null);
					result.success(true);
				} catch (IOException e) {
					// Log the error.
					Log.e("nearby_connections", e.getMessage());
					result.success(false);
				}
				break;
			case "stopAdvertising":
				Log.d("nearby_connections", "stopAdvertising");
				Nearby.getConnectionsClient(activity).stopAdvertising();
				result.success(null);
				break;
			case "stopDiscovery":
				Log.d("nearby_connections", "stopDiscovery");
				Nearby.getConnectionsClient(activity).stopDiscovery();
				result.success(null);
				break;
			case "startAdvertising": {
				String userNickName = (String) call.argument("userNickName");
				int strategy = (int) call.argument("strategy");
				String serviceId = (String) call.argument("serviceId");
				advertisingStrategy = strategy;

				assert userNickName != null;
				if (serviceId == null || serviceId == "")
					serviceId = SERVICE_ID;

				AdvertisingOptions advertisingOptions = new AdvertisingOptions.Builder()
						.setStrategy(getStrategy(strategy)).build();

				Nearby.getConnectionsClient(activity).startAdvertising(userNickName, serviceId,
								advertConnectionLifecycleCallback, advertisingOptions)
						.addOnSuccessListener(new OnSuccessListener<Void>() {
							@Override
							public void onSuccess(Void aVoid) {
								Log.d("nearby_connections", "startAdvertising");
								result.success(true);
							}
						}).addOnFailureListener(new OnFailureListener() {
							@Override
							public void onFailure(@NonNull Exception e) {
								result.error("Failure", e.getMessage(), null);
							}
						});
				break;
			}
			case "startDiscovery": {
				String userNickName = (String) call.argument("userNickName");
				int strategy = (int) call.argument("strategy");
				String serviceId = (String) call.argument("serviceId");
				discoveryStrategy = strategy;

				assert userNickName != null;
				if (serviceId == null || serviceId == "")
					serviceId = SERVICE_ID;

				DiscoveryOptions discoveryOptions = new DiscoveryOptions.Builder().setStrategy(getStrategy(strategy))
						.build();
				Nearby.getConnectionsClient(activity)
						.startDiscovery(serviceId, endpointDiscoveryCallback, discoveryOptions)
						.addOnSuccessListener(new OnSuccessListener<Void>() {
							@Override
							public void onSuccess(Void aVoid) {
								Log.d("nearby_connections", "startDiscovery");
								result.success(true);
							}
						}).addOnFailureListener(new OnFailureListener() {
							@Override
							public void onFailure(@NonNull Exception e) {
								result.error("Failure", e.getMessage(), null);
							}
						});
				break;
			}
			case "stopAllEndpoints":
				Log.d("nearby_connections", "stopAllEndpoints");
				Nearby.getConnectionsClient(activity).stopAllEndpoints();
				result.success(null);
				break;
			case "disconnectFromEndpoint": {
				Log.d("nearby_connections", "disconnectFromEndpoint");
				String endpointId = call.argument("endpointId");
				assert endpointId != null;
				Nearby.getConnectionsClient(activity).disconnectFromEndpoint(endpointId);
				result.success(null);
				break;
			}
			case "requestConnection": {
				Log.d("nearby_connections", "requestConnection");
				String userNickName = (String) call.argument("userNickName");
				String endpointId = (String) call.argument("endpointId");
				String traceId = (String) call.argument("connectionTraceId");
				connectionStartedAt.put(endpointId, SystemClock.elapsedRealtime());
				connectionOperations.put(endpointId, "requestConnection");
				if (traceId != null) connectionTraceIds.put(endpointId, traceId);
				emitNativeDiagnostic("native_request_connection_started", endpointId,
						"requestConnection", null, null);

				assert userNickName != null;
				assert endpointId != null;
				Nearby.getConnectionsClient(activity)
						.requestConnection(userNickName, endpointId, discoverConnectionLifecycleCallback)
						.addOnSuccessListener(new OnSuccessListener<Void>() {
							@Override
							public void onSuccess(Void aVoid) {
							emitNativeDiagnostic("native_request_connection_task_success", endpointId,
									"requestConnection", null, null);
								result.success(true);
							}
						}).addOnFailureListener(new OnFailureListener() {
							@Override
							public void onFailure(@NonNull Exception e) {
								emitNativeDiagnostic("native_request_connection_task_failed", endpointId,
										"requestConnection", statusCode(e),
										statusCode(e) < 0 ? null : nearbyStatusName(statusCode(e)), safeMessage(e));
								result.error("NearbyApiException", safeMessage(e), failureDetails("requestConnection", e));
							}
						});
				break;
			}
			case "acceptConnection": {
				String endpointId = (String) call.argument("endpointId");
				String traceId = (String) call.argument("connectionTraceId");
				connectionOperations.put(endpointId, "acceptConnection");
				if (traceId != null) connectionTraceIds.put(endpointId, traceId);
				emitNativeDiagnostic("native_accept_connection_started", endpointId,
						"acceptConnection", null, null);

				assert endpointId != null;
				Nearby.getConnectionsClient(activity).acceptConnection(endpointId, payloadCallback)
						.addOnSuccessListener(new OnSuccessListener<Void>() {
							@Override
							public void onSuccess(Void aVoid) {
								Log.d("nearby_connections", "acceptConnection");
								emitNativeDiagnostic("native_accept_connection_task_success", endpointId,
										"acceptConnection", null, null);
								result.success(true);
							}
						}).addOnFailureListener(new OnFailureListener() {
							@Override
							public void onFailure(@NonNull Exception e) {
								emitNativeDiagnostic("native_accept_connection_task_failed", endpointId,
										"acceptConnection", statusCode(e),
										statusCode(e) < 0 ? null : nearbyStatusName(statusCode(e)), safeMessage(e));
								result.error("NearbyApiException", safeMessage(e), failureDetails("acceptConnection", e));
							}
						});
				break;
			}
			case "rejectConnection": {
				String endpointId = (String) call.argument("endpointId");

				assert endpointId != null;
				Nearby.getConnectionsClient(activity).rejectConnection(endpointId)
						.addOnSuccessListener(new OnSuccessListener<Void>() {
							@Override
							public void onSuccess(Void aVoid) {
								Log.d("nearby_connections", "rejectConnection");
								result.success(true);
							}
						}).addOnFailureListener(new OnFailureListener() {
							@Override
							public void onFailure(@NonNull Exception e) {
								result.error("Failure", e.getMessage(), null);
							}
						});
				break;
			}
			case "sendPayload": {
				String endpointId = (String) call.argument("endpointId");
				byte[] bytes = call.argument("bytes");

				assert endpointId != null;
				assert bytes != null;
				Nearby.getConnectionsClient(activity).sendPayload(endpointId, Payload.fromBytes(bytes));
				Log.d("nearby_connections", "sentPayload");
				result.success(true);
				break;
			}
			case "sendFilePayload": {
				String endpointId = (String) call.argument("endpointId");
				String filePath = (String) call.argument("filePath");

				assert endpointId != null;
				assert filePath != null;

				try {
					File file = new File(filePath);

					Payload filePayload = Payload.fromFile(file);
					Nearby.getConnectionsClient(activity).sendPayload(endpointId, filePayload);
					Log.d("nearby_connections", "sentFilePayload");
					result.success(filePayload.getId()); // return payload id to dart
				} catch (FileNotFoundException e) {
					Log.e("nearby_connections", "File not found", e);
					result.error("Failure", e.getMessage(), null);
					return;
				}
				break;
			}
			case "cancelPayload": {
				String payloadId = (String) call.argument("payloadId");
				assert payloadId != null;
				Nearby.getConnectionsClient(activity).cancelPayload(Long.parseLong(payloadId));
				Log.d("nearby_connections", "cancelPayload");
				result.success(null);
				break;
			}
			default:
				result.notImplemented();
		}
	}

	private final ConnectionLifecycleCallback advertConnectionLifecycleCallback = new ConnectionLifecycleCallback() {
		@Override
		public void onConnectionInitiated(@NonNull String endpointId, @NonNull ConnectionInfo connectionInfo) {
			Log.d("nearby_connections", "ad.onConnectionInitiated");
			connectionStartedAt.putIfAbsent(endpointId, SystemClock.elapsedRealtime());
			incomingConnections.put(endpointId, connectionInfo.isIncomingConnection());
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);
			args.put("endpointName", connectionInfo.getEndpointName());
			args.put("authenticationToken", connectionInfo.getAuthenticationToken());
			args.put("isIncomingConnection", connectionInfo.isIncomingConnection());

			args.put("method", "ad.onConnectionInitiated");
			sendEvent(args);
		}

		@Override
		public void onConnectionResult(@NonNull String endpointId, @NonNull ConnectionResolution connectionResolution) {
			Log.d("nearby_connections", "ad.onConnectionResult");
			emitConnectionResolution(endpointId, connectionResolution, "ad.onConnectionResult", advertisingStrategy);
		}

		@Override
		public void onDisconnected(@NonNull String endpointId) {
			Log.d("nearby_connections", "ad.onDisconnected");
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);

			args.put("method", "ad.onDisconnected");
			sendEvent(args);
		}
	};

	private final ConnectionLifecycleCallback discoverConnectionLifecycleCallback = new ConnectionLifecycleCallback() {
		@Override
		public void onConnectionInitiated(@NonNull String endpointId, @NonNull ConnectionInfo connectionInfo) {
			Log.d("nearby_connections", "dis.onConnectionInitiated");
			connectionStartedAt.putIfAbsent(endpointId, SystemClock.elapsedRealtime());
			incomingConnections.put(endpointId, connectionInfo.isIncomingConnection());
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);
			args.put("endpointName", connectionInfo.getEndpointName());
			args.put("authenticationToken", connectionInfo.getAuthenticationToken());
			args.put("isIncomingConnection", connectionInfo.isIncomingConnection());

			args.put("method", "dis.onConnectionInitiated");
			sendEvent(args);
		}

		@Override
		public void onConnectionResult(@NonNull String endpointId, @NonNull ConnectionResolution connectionResolution) {
			Log.d("nearby_connections", "dis.onConnectionResult");
			emitConnectionResolution(endpointId, connectionResolution, "dis.onConnectionResult", discoveryStrategy);
		}

		@Override
		public void onDisconnected(@NonNull String endpointId) {
			Log.d("nearby_connections", "dis.onDisconnected");
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);

			args.put("method","dis.onDisconnected");
			sendEvent(args);
		}
	};

	private final PayloadCallback payloadCallback = new PayloadCallback() {
		@Override
		public void onPayloadReceived(@NonNull String endpointId, @NonNull Payload payload) {
			Log.d("nearby_connections", "onPayloadReceived");
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);
			args.put("payloadId", payload.getId());
			args.put("type", payload.getType());

			if (payload.getType() == Payload.Type.BYTES) {
				byte[] bytes = payload.asBytes();
				assert bytes != null;
				args.put("bytes", bytes);
			} else if (payload.getType() == Payload.Type.FILE) {
				args.put("uri", payload.asFile().asUri().toString());
				if (VERSION.SDK_INT < VERSION_CODES.Q) {
					// This is deprecated and only available on Android 10 and below.
					args.put("filePath", payload.asFile().asJavaFile().getAbsolutePath());
				}
			}


			args.put("method","onPayloadReceived");
			sendEvent(args);
		}

		@Override
		public void onPayloadTransferUpdate(@NonNull String endpointId,
											@NonNull PayloadTransferUpdate payloadTransferUpdate) {
			// required for files and streams

			Log.d("nearby_connections", "onPayloadTransferUpdate");
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);
			args.put("payloadId", payloadTransferUpdate.getPayloadId());
			args.put("status", payloadTransferUpdate.getStatus());
			args.put("bytesTransferred", payloadTransferUpdate.getBytesTransferred());
			args.put("totalBytes", payloadTransferUpdate.getTotalBytes());

			args.put("method","onPayloadTransferUpdate");
			sendEvent(args);
		}
	};

	private final EndpointDiscoveryCallback endpointDiscoveryCallback = new EndpointDiscoveryCallback() {
		@Override
		public void onEndpointFound(@NonNull String endpointId,
									@NonNull DiscoveredEndpointInfo discoveredEndpointInfo) {
			Log.d("nearby_connections", "onEndpointFound");
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);
			args.put("endpointName", discoveredEndpointInfo.getEndpointName());
			args.put("serviceId", discoveredEndpointInfo.getServiceId());

			args.put("method","dis.onEndpointFound");
			sendEvent(args);
		}

		@Override
		public void onEndpointLost(@NonNull String endpointId) {
			Log.d("nearby_connections", "onEndpointLost");
			Map<String, Object> args = new HashMap<>();
			args.put("endpointId", endpointId);

			args.put("method","dis.onEndpointLost");
			sendEvent(args);
		}
	};

	private void emitConnectionResolution(String endpointId, ConnectionResolution resolution,
			String method, int strategy) {
		int rawCode = resolution.getStatus().getStatusCode();
		String rawName = nearbyStatusName(rawCode);
		Map<String, Object> args = new HashMap<>();
		args.put("endpointId", endpointId);
		args.put("statusCode", rawCode == ConnectionsStatusCodes.STATUS_OK ? 0
				: rawCode == ConnectionsStatusCodes.STATUS_CONNECTION_REJECTED ? 1 : 2);
		args.put("rawStatusCode", rawCode);
		args.put("rawStatusName", rawName);
		String message = resolution.getStatus().getStatusMessage();
		if (message != null) args.put("rawStatusMessage", message);
		args.put("operation", connectionOperations.getOrDefault(endpointId, "onConnectionResult"));
		args.put("role", Boolean.TRUE.equals(incomingConnections.get(endpointId)) ? "responder" : "initiator");
		Long started = connectionStartedAt.get(endpointId);
		if (started != null) args.put("elapsedMs", Math.max(0L, SystemClock.elapsedRealtime() - started));
		args.put("strategy", strategyName(strategy));
		args.put("endpointAlias", endpointAlias(endpointId));
		args.putAll(getNearbyDiagnostics());
		String traceId = connectionTraceIds.get(endpointId);
		if (traceId != null) {
			args.put("connectionTraceId", traceId);
			args.put("traceId", traceId);
		}
		args.put("method", method);
		sendEvent(args);
		emitNativeDiagnostic("native_connection_resolution_received", endpointId,
				String.valueOf(args.get("operation")), rawCode, rawName, message);
		emitNativeDiagnostic("native_raw_status", endpointId,
				String.valueOf(args.get("operation")), rawCode, rawName, message);
		connectionStartedAt.remove(endpointId);
		connectionTraceIds.remove(endpointId);
		connectionOperations.remove(endpointId);
		incomingConnections.remove(endpointId);
	}

	private Map<String, Object> getNearbyDiagnostics() {
		Map<String, Object> snapshot = new HashMap<>();
		snapshot.put("androidApi", VERSION.SDK_INT);
		snapshot.put("nearbyLibraryVersion", "4.3.0");
		snapshot.put("playServicesNearbyDependencyVersion", "19.2.0");
		snapshot.put("advertisingStrategy", strategyName(advertisingStrategy));
		snapshot.put("discoveryStrategy", strategyName(discoveryStrategy));
		try {
			PackageInfo info = activity.getPackageManager().getPackageInfo("com.google.android.gms", 0);
			snapshot.put("googlePlayServicesAvailable", true);
			snapshot.put("googlePlayServicesVersionName", info.versionName == null ? "unknown" : info.versionName);
			snapshot.put("googlePlayServicesVersionCode", VERSION.SDK_INT >= 28
					? info.getLongVersionCode() : (long) info.versionCode);
		} catch (Exception error) {
			snapshot.put("googlePlayServicesAvailable", false);
			snapshot.put("googlePlayServicesError", error.getClass().getSimpleName());
		}
		return snapshot;
	}

	private void emitNativeDiagnostic(String name, String endpointId, String operation,
			Integer rawCode, String rawName) {
		emitNativeDiagnostic(name, endpointId, operation, rawCode, rawName, null);
	}

	private void emitNativeDiagnostic(String name, String endpointId, String operation,
			Integer rawCode, String rawName, String rawMessage) {
		Map<String, Object> event = new HashMap<>();
		event.put("method", "native.diagnostic");
		event.put("name", name);
		event.put("operation", operation);
		event.put("role", Boolean.TRUE.equals(incomingConnections.get(endpointId))
				? "responder" : "initiator");
		event.put("endpointAlias", endpointAlias(endpointId));
		Long started = connectionStartedAt.get(endpointId);
		if (started != null) event.put("elapsedMs", Math.max(0L, SystemClock.elapsedRealtime() - started));
		event.put("strategy", strategyName("acceptConnection".equals(operation)
				? advertisingStrategy : discoveryStrategy));
		event.putAll(getNearbyDiagnostics());
		String traceId = connectionTraceIds.get(endpointId);
		if (traceId != null) {
			event.put("connectionTraceId", traceId);
			event.put("traceId", traceId);
		}
		if (rawCode != null) event.put("rawStatusCode", rawCode);
		if (rawName != null) event.put("rawStatusName", rawName);
		if (rawMessage != null) event.put("rawStatusMessage", rawMessage);
		sendEvent(event);
	}

	private void sendEvent(Map<String, Object> event) {
		EventChannel.EventSink sink = eventSink;
		if (sink != null) sink.success(event);
	}

	private String endpointAlias(String endpointId) {
		return "endpoint-" + Integer.toHexString(endpointId.hashCode());
	}

	private String strategyName(int strategy) {
		switch (strategy) {
			case 0: return "P2P_CLUSTER";
			case 1: return "P2P_STAR";
			case 2: return "P2P_POINT_TO_POINT";
			default: return "UNKNOWN_STRATEGY_" + strategy;
		}
	}

	private int statusCode(Exception error) {
		return error instanceof ApiException ? ((ApiException) error).getStatusCode() : -1;
	}

	private String nearbyStatusName(int code) {
		String name = ConnectionsStatusCodes.getStatusCodeString(code);
		if (name == null || name.isEmpty() || !name.matches("[A-Z][A-Z0-9_]*")) {
			return "UNKNOWN_STATUS_" + code;
		}
		return name;
	}

	private String safeMessage(Exception error) {
		String message = error.getMessage();
		return message == null ? error.getClass().getSimpleName() : message;
	}

	private Map<String, Object> failureDetails(String operation, Exception error) {
		Map<String, Object> details = new HashMap<>();
		details.put("operation", operation);
		details.put("exceptionClass", error.getClass().getSimpleName());
		int code = statusCode(error);
		if (code >= 0) {
			details.put("rawStatusCode", code);
			details.put("rawStatusName", nearbyStatusName(code));
			details.put("rawStatusMessage", safeMessage(error));
		}
		return details;
	}

	private Strategy getStrategy(int strategy) {
		switch (strategy) {
			case 0:
				return Strategy.P2P_CLUSTER;
			case 1:
				return Strategy.P2P_STAR;
			case 2:
				return Strategy.P2P_POINT_TO_POINT;
			default:
				return Strategy.P2P_CLUSTER;
		}
	}

	@Override
	public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
		channel = new MethodChannel(binding.getBinaryMessenger(), "nearby_connections");
		channel.setMethodCallHandler(this);
		eventChannel=new EventChannel(binding.getBinaryMessenger(), "nearby_connections/events");
		eventChannel.setStreamHandler(
				new EventChannel.StreamHandler() {
					@Override
					public void onListen(Object arguments, EventChannel.EventSink events) {
						eventSink=events;
					}
					@Override
					public void onCancel(Object arguments) {
						eventSink=null;
					}
				});
	}

	@Override
	public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
	}

	@Override
	public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
		this.activity = binding.getActivity();
	}

	@Override
	public void onDetachedFromActivity() {
	}

	@Override
	public void onDetachedFromActivityForConfigChanges() {
	}

	@Override
	public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
		this.activity = binding.getActivity();
	}

	/** Copies a stream from one location to another. */
	private static void copyStream(InputStream in, OutputStream out) throws IOException {
		try {
			byte[] buffer = new byte[1024];
			int read;
			while ((read = in.read(buffer)) != -1) {
				out.write(buffer, 0, read);
			}
			out.flush();
		} finally {
			in.close();
			out.close();
		}
	}
}
