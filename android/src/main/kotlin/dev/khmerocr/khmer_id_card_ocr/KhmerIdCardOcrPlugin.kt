package dev.khmerocr.khmer_id_card_ocr

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class KhmerIdCardOcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var assets: FlutterPlugin.FlutterAssets
    private val main = Handler(Looper.getMainLooper())
    private lateinit var nameRecognizer: KhmerNameRecognizer
    private lateinit var executor: java.util.concurrent.ExecutorService

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        assets = binding.flutterAssets
        executor = Executors.newSingleThreadExecutor()
        nameRecognizer = KhmerNameRecognizer(context, assets)
        channel = MethodChannel(binding.binaryMessenger, "khmer_id_card_ocr")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        val recognizer = nameRecognizer
        executor.execute { recognizer.close() }
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognize") {
            result.notImplemented()
            return
        }
        val images = regions.keys.mapNotNull { key ->
            call.argument<ByteArray>(key)?.let { key to it }
        }.toMap()
        val name = textTensor(
            call.argument<FloatArray>("nameInput"),
            call.argument<Int>("nameWidth"),
            call.argument<Int>("nameHeight"),
        )
        if (regions.any { (key, region) -> region.required && key !in images } || name == null) {
            result.error("INVALID_IMAGE", "The OCR image regions are missing or invalid.", null)
            return
        }
        val nameLine = call.argument<Map<String, Any>>("nameLine")?.let(::textTensor)
        val latinNameLine = call.argument<Map<String, Any>>("latinNameLine")?.let(::textTensor)
        val birthplaceLine = call.argument<Map<String, Any>>("birthplaceLine")?.let(::textTensor)
        val validityLine = call.argument<Map<String, Any>>("validityLine")?.let(::textTensor)
        val addressDetail = call.argument<Map<String, Any>>("addressDetailLine")?.let(::textTensor)
        val addressLines = call.argument<List<Map<String, Any>>>("addressLines")
            .orEmpty().take(2).mapNotNull(::textTensor)

        val recognizer = nameRecognizer
        executor.execute {
            try {
                val dataDir = prepareModels()
                val output = mutableMapOf<String, Any>()
                for ((language, entries) in regions.entries.groupBy { it.value.language }) {
                    val engine = TessBaseAPI()
                    try {
                        check(engine.init(dataDir.absolutePath, language, TessBaseAPI.OEM_LSTM_ONLY))
                        for ((key, region) in entries) {
                            val bytes = images[key] ?: continue
                            val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                ?: error("Could not decode the OCR image region.")
                            try {
                                engine.setPageSegMode(region.mode)
                                engine.setVariable("tessedit_char_whitelist", region.whitelist)
                                engine.setImage(image)
                                output[key] = engine.utF8Text.orEmpty()
                                engine.clear()
                            } finally {
                                image.recycle()
                            }
                        }
                    } finally {
                        engine.recycle()
                    }
                }
                output["nameScores"] = recognizer.read(name.input, name.width, name.height)
                if (nameLine != null) {
                    output["nameLineScores"] =
                        recognizer.read(nameLine.input, nameLine.width, nameLine.height)
                }
                if (latinNameLine != null) {
                    output["latinNameLineScores"] =
                        recognizer.read(latinNameLine.input, latinNameLine.width, latinNameLine.height)
                }
                if (birthplaceLine != null) {
                    output["birthplaceLineScores"] =
                        recognizer.read(birthplaceLine.input, birthplaceLine.width, birthplaceLine.height)
                }
                if (addressLines.isNotEmpty()) {
                    output["addressLineScores"] = addressLines.map { line ->
                        recognizer.read(line.input, line.width, line.height)
                    }
                }
                if (validityLine != null) {
                    output["validityLineScores"] =
                        recognizer.read(validityLine.input, validityLine.width, validityLine.height)
                }
                if (addressDetail != null) {
                    output["addressDetailLineScores"] =
                        recognizer.read(addressDetail.input, addressDetail.width, addressDetail.height)
                }
                main.post { result.success(output) }
            } catch (_: Exception) {
                main.post { result.error("OCR_FAILED", "Could not read the card on this device.", null) }
            } catch (_: LinkageError) {
                main.post { result.error("OCR_UNAVAILABLE", "The native OCR engine could not load.", null) }
            }
        }
    }

    private data class TextTensor(val input: FloatArray, val width: Int, val height: Int)

    private fun textTensor(line: Map<String, Any>): TextTensor? =
        textTensor(line["input"] as? FloatArray, line["width"] as? Int, line["height"] as? Int)

    private fun textTensor(input: FloatArray?, width: Int?, height: Int?): TextTensor? {
        if (input == null || width == null || height == null ||
            width !in 48..960 || height !in 48..64 || input.size != 3 * width * height
        ) return null
        return TextTensor(input, width, height)
    }

    private fun prepareModels(): File = synchronized(modelLock) {
        val root = File(context.noBackupFilesDir, "khmer_id_card_ocr_v1")
        val folder = File(root, "tessdata")
        check(folder.isDirectory || folder.mkdirs())
        for (language in listOf("eng", "khm")) {
            val filename = "$language.traineddata"
            val target = File(folder, filename)
            if (target.isFile && target.length() > 0) continue
            val temporary = File.createTempFile(language, ".tmp", folder)
            try {
                val asset = assets.getAssetFilePathByName("assets/tessdata/$filename", "khmer_id_card_ocr")
                context.assets.open(asset).use { input ->
                    temporary.outputStream().use { output -> input.copyTo(output) }
                }
                check(temporary.renameTo(target))
            } finally {
                temporary.delete()
            }
        }
        root
    }

    private data class Region(
        val language: String, val mode: Int, val whitelist: String = "", val required: Boolean = true,
    )

    companion object {
        private val modelLock = Any()
        private const val mrzWhitelist = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<"
        private val regions = mapOf(
            "mrz" to Region("eng", 6, mrzWhitelist),
            "mrzWide" to Region("eng", 6, mrzWhitelist, required = false),
            "mrzCheck" to Region("eng", 10, "0123456789", required = false),
            "printed" to Region("khm+eng", 11),
            "id" to Region("eng", 7, "0123456789"),
            "nameEn" to Region("eng", 7),
        )
    }
}
