package dev.khmerocr.khmer_id_card_ocr

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.File
import java.nio.FloatBuffer

/** Called on the plugin's OCR executor. */
internal class KhmerNameRecognizer(
    private val context: Context,
    private val assets: FlutterPlugin.FlutterAssets,
) : AutoCloseable {
    private var session: OrtSession? = null

    fun read(pixels: FloatArray, width: Int, height: Int): FloatArray {
        val env = OrtEnvironment.getEnvironment()
        val model = session ?: OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            env.createSession(prepareModel().absolutePath, options)
        }.also { session = it }
        val shape = longArrayOf(1, 3, height.toLong(), width.toLong())
        return OnnxTensor.createTensor(env, FloatBuffer.wrap(pixels), shape).use { input ->
            model.run(mapOf("image" to input)).use { output ->
                val tensor = output.get("probs").orElseThrow() as OnnxTensor
                val scores = tensor.floatBuffer
                FloatArray(scores.remaining()).also { scores.get(it) }
            }
        }
    }

    override fun close() {
        session?.close()
        session = null
    }

    private fun prepareModel(): File = synchronized(assetLock) {
        val folder = File(context.noBackupFilesDir, "khmer_id_card_ocr_v1")
        check(folder.isDirectory || folder.mkdirs() || folder.isDirectory)
        val model = File(folder, modelFilename)
        if (model.isFile && model.length() > 0) return@synchronized model

        val asset = assets.getAssetFilePathByName(
            "assets/recognition/$modelFilename",
            "khmer_id_card_ocr",
        )
        val temporary = File.createTempFile("name-model", ".tmp", folder)
        try {
            context.assets.open(asset).use { source ->
                temporary.outputStream().use { destination -> source.copyTo(destination) }
            }
            check(temporary.renameTo(model))
        } finally {
            temporary.delete()
        }
        model
    }

    companion object {
        private const val modelFilename = "khmer-name-svtrv2-v4-int8.onnx"
        private val assetLock = Any()
    }
}
