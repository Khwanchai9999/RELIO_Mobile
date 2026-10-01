package com.relio.relio_mobile

import android.util.Base64
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.X509EncodedKeySpec

/** กุญแจส่วนตัวใช้ลงนามใน Android Keystore และไม่ถูกส่งออกจากเครื่อง */
internal class RelioIdentityKeyStore {
    data class PublicIdentity(val publicKey: String, val fingerprint: String)

    fun getOrCreatePublicIdentity(): PublicIdentity {
        val store = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (!store.containsAlias(KEY_ALIAS)) {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                ANDROID_KEYSTORE,
            )
            generator.initialize(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            generator.generateKeyPair()
        }
        val encoded = store.getCertificate(KEY_ALIAS)?.publicKey?.encoded
            ?: error("Identity public key unavailable")
        return PublicIdentity(
            publicKey = encode(encoded),
            fingerprint = fingerprint(encoded),
        )
    }

    fun sign(message: ByteArray): String {
        require(message.size in 1..MAX_MESSAGE_BYTES)
        val store = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val privateKey = store.getKey(KEY_ALIAS, null)
            ?: error("Identity signing key unavailable")
        val signer = Signature.getInstance(SIGNATURE_ALGORITHM)
        signer.initSign(privateKey as java.security.PrivateKey)
        signer.update(message)
        return encode(signer.sign())
    }

    fun verify(publicKey: String, message: ByteArray, signature: String): Boolean {
        if (message.isEmpty() || message.size > MAX_MESSAGE_BYTES) return false
        return runCatching {
            verifyEncoded(publicKey, message, signature)
        }.getOrDefault(false)
    }

    fun fingerprint(publicKey: String): String = fingerprint(decode(publicKey))

    internal fun verifyEncoded(
        publicKey: String,
        message: ByteArray,
        signature: String,
    ): Boolean {
        val decodedKey = decode(publicKey)
        val decodedSignature = decode(signature)
        require(decodedSignature.size in 8..MAX_SIGNATURE_BYTES)
        val key = KeyFactory.getInstance(KEY_ALGORITHM).generatePublic(
            X509EncodedKeySpec(decodedKey),
        )
        val verifier = Signature.getInstance(SIGNATURE_ALGORITHM)
        verifier.initVerify(key)
        verifier.update(message)
        return verifier.verify(decodedSignature)
    }

    private fun fingerprint(encodedPublicKey: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(encodedPublicKey)
            .joinToString("") { byte -> "%02x".format(byte) }

    private fun decode(value: String): ByteArray {
        require(value.length in 8..MAX_ENCODED_BYTES)
        return Base64.decode(value, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    private fun encode(value: ByteArray): String =
        Base64.encodeToString(value, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "relio.device.identity.v1"
        const val KEY_ALGORITHM = "EC"
        const val SIGNATURE_ALGORITHM = "SHA256withECDSA"
        const val MAX_MESSAGE_BYTES = 4096
        const val MAX_SIGNATURE_BYTES = 256
        const val MAX_ENCODED_BYTES = 2048
    }
}
