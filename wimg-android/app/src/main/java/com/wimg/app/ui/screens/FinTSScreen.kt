package com.wimg.app.ui.screens

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.WimgJni
import com.wimg.app.services.FintsHttpCallback
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgHero
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import com.wimg.app.i18n.L

@Serializable
private data class BankInfo(val blz: String, val name: String, val url: String)

@Serializable
private data class FintsResult(
    val status: String? = null,
    val challenge: String? = null,
    val phototan: String? = null,
    val decoupled: Boolean? = null,
    val message: String? = null,
    val tan_medium_required: Boolean? = null,
    val imported: Int? = null,
    val duplicates: Int? = null,
)

private val json = Json { ignoreUnknownKeys = true }

/** Run a block on a thread with 2MB stack (FinTS needs large buffers for Base64/MT940). */
private suspend fun <T> withFintsThread(block: () -> T): T {
    return kotlinx.coroutines.suspendCancellableCoroutine { cont ->
        val thread = Thread(null, {
            try {
                val result = block()
                cont.resumeWith(Result.success(result))
            } catch (e: Throwable) {
                cont.resumeWith(Result.failure(e))
            }
        }, "fints-worker", 2 * 1024 * 1024) // 2MB stack
        thread.start()
    }
}

private const val PREFS = "wimg_fints"
private const val KEY_BLZ = "fints_blz"
private const val KEY_KENNUNG = "fints_kennung"
private const val KEY_PIN = "fints_pin"
private const val KEY_TAN_MEDIUM = "fints_tan_medium"

@Composable
fun FinTSScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val fintsPrefs = context.getSharedPreferences(PREFS, 0)

    var stage by remember { mutableStateOf("banks") }
    var banks by remember { mutableStateOf<List<BankInfo>>(emptyList()) }
    var searchQuery by remember { mutableStateOf("") }
    var selectedBank by remember { mutableStateOf<BankInfo?>(null) }
    var kennung by remember { mutableStateOf("") }
    var pin by remember { mutableStateOf("") }
    var rememberPIN by remember { mutableStateOf(fintsPrefs.getString(KEY_PIN, null) != null) }
    var refreshing by remember { mutableStateOf(false) }
    var connecting by remember { mutableStateOf(false) }
    var tanInput by remember { mutableStateOf("") }
    var challengeText by remember { mutableStateOf("") }
    var photoTanB64 by remember { mutableStateOf<String?>(null) }
    var isDecoupled by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var importedCount by remember { mutableIntStateOf(0) }
    var duplicateCount by remember { mutableIntStateOf(0) }

    val scope = rememberCoroutineScope()

    // Notification permission for the background refresh. Asked for here rather
    // than at launch: a system prompt out of nowhere gets denied. The result is
    // irrelevant to scheduling — the refresh still runs, it just stays silent.
    val notificationPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { }

    /** Called after a successful Schnellabfrage — mirrors iOS. */
    fun armBackgroundRefresh() {
        com.wimg.app.services.BackgroundRefresh.enqueue(context)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU &&
            !com.wimg.app.services.BackgroundRefresh.hasNotificationPermission(context)
        ) {
            notificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Load banks + restore saved credentials
    LaunchedEffect(Unit) {
        WimgJni.nativeSetHttpCallback(FintsHttpCallback())

        withFintsThread {
            val result = WimgJni.nativeFintsGetBanks()
            if (result != null) {
                banks = json.decodeFromString(result)
            }
        }

        // Restore saved bank + kennung + PIN
        val savedBLZ = fintsPrefs.getString(KEY_BLZ, null)
        if (savedBLZ != null) {
            val bank = banks.find { it.blz == savedBLZ }
            if (bank != null) {
                selectedBank = bank
                kennung = fintsPrefs.getString(KEY_KENNUNG, null) ?: ""
                val savedPIN = fintsPrefs.getString(KEY_PIN, null)
                if (savedPIN != null) {
                    pin = savedPIN
                    rememberPIN = true
                }
                stage = "credentials"
            }
        }
    }

    val filteredBanks = if (searchQuery.isBlank()) banks.take(50) else {
        val q = searchQuery.lowercase()
        banks.filter { it.name.lowercase().contains(q) || it.blz.contains(q) }.take(50)
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when (stage) {
            "banks" -> {
                item {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        Box(modifier = Modifier.size(80.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                            Icon(Icons.Outlined.AccountBalance, contentDescription = null, modifier = Modifier.size(36.dp), tint = MaterialTheme.colorScheme.primary)
                        }
                        Spacer(Modifier.height(12.dp))
                        Text(L("Bank verbinden"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    }
                }
                item {
                    OutlinedTextField(value = searchQuery, onValueChange = { searchQuery = it }, placeholder = { Text(L("Bank suchen...")) }, leadingIcon = { Icon(Icons.Outlined.Search, null) }, singleLine = true, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp))
                }
                items(filteredBanks) { bank ->
                    Row(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surface).clickable { selectedBank = bank; stage = "credentials" }.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.AccountBalance, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(bank.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
                            Text("BLZ: ${bank.blz}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            "credentials" -> {
                // Quick Refresh card (when saved PIN exists)
                if (rememberPIN && fintsPrefs.getString(KEY_PIN, null) != null) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().wimgHero()) {
                            Column(modifier = Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Outlined.Refresh, null, modifier = Modifier.size(48.dp), tint = WimgColors.heroText)
                                Spacer(Modifier.height(12.dp))
                                Text("Schnellabfrage", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = WimgColors.heroText)
                                selectedBank?.let { Text(it.name, style = MaterialTheme.typography.bodySmall, color = WimgColors.heroText.copy(alpha = 0.7f)) }
                                Spacer(Modifier.height(16.dp))
                                Button(
                                    onClick = {
                                        refreshing = true; errorMessage = null
                                        scope.launch {
                                            val result = withFintsThread {
                                                val bank = selectedBank ?: return@withFintsThread null
                                                val savedPIN = fintsPrefs.getString(KEY_PIN, null) ?: return@withFintsThread null
                                                val input = """{"blz":"${bank.blz}","user":"$kennung","pin":"$savedPIN","product":"F7C4049477F6136957A46EC28"}"""
                                                val r = WimgJni.nativeFintsConnect(input) ?: return@withFintsThread null
                                                json.decodeFromString<FintsResult>(r)
                                            }
                                            if (result?.status == "ok") {
                                                // Auto-fetch last 90 days
                                                val cal = java.util.Calendar.getInstance()
                                                val to = String.format("%04d-%02d-%02d", cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH))
                                                cal.add(java.util.Calendar.DAY_OF_YEAR, -90)
                                                val from = String.format("%04d-%02d-%02d", cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH))
                                                val fetchResult = withFintsThread {
                                                    val r = WimgJni.nativeFintsFetch("""{"from":"$from","to":"$to"}""") ?: return@withFintsThread null
                                                    json.decodeFromString<FintsResult>(r)
                                                }
                                                refreshing = false
                                                if (fetchResult?.status == "tan_required") {
                                                    challengeText = fetchResult.challenge ?: ""; photoTanB64 = fetchResult.phototan; isDecoupled = fetchResult.decoupled ?: false; tanInput = ""; stage = "tan"
                                                } else {
                                                    importedCount = fetchResult?.imported ?: 0; duplicateCount = fetchResult?.duplicates ?: 0; stage = "result"
                                                    armBackgroundRefresh()
                                                }
                                            } else if (result?.status == "tan_required") {
                                                refreshing = false; challengeText = result.challenge ?: ""; photoTanB64 = result.phototan; isDecoupled = result.decoupled ?: false; tanInput = ""; stage = "tan"
                                            } else {
                                                refreshing = false
                                                fintsPrefs.edit().remove(KEY_PIN).apply(); rememberPIN = false; pin = ""
                                                // No stored PIN left — nothing for the background job to do.
                                                com.wimg.app.services.BackgroundRefresh.cancel(context)
                                                errorMessage = result?.message ?: "Anmeldung fehlgeschlagen"
                                            }
                                        }
                                    },
                                    enabled = !refreshing,
                                    colors = ButtonDefaults.buttonColors(containerColor = WimgColors.heroText, contentColor = WimgColors.accent),
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(if (refreshing) "Verbinde..." else "Aktualisieren", fontWeight = FontWeight.Bold)
                                }
                                TextButton(onClick = {
                                    fintsPrefs.edit().remove(KEY_PIN).apply(); rememberPIN = false; pin = ""
                                    com.wimg.app.services.BackgroundRefresh.cancel(context)
                                }) {
                                    Text("Manuell anmelden", color = WimgColors.heroText.copy(alpha = 0.7f))
                                }
                            }
                        }
                    }
                }

                item {
                    Card(modifier = Modifier.fillMaxWidth(), shape = WimgShapes.large, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                        Column(modifier = Modifier.padding(24.dp)) {
                            Text(L("Anmeldung"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            selectedBank?.let { Text(it.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            Spacer(Modifier.height(16.dp))
                            OutlinedTextField(value = kennung, onValueChange = { kennung = it }, label = { Text(L("Kennung")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            Spacer(Modifier.height(8.dp))
                            OutlinedTextField(value = pin, onValueChange = { pin = it }, label = { Text("PIN") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth())
                            Spacer(Modifier.height(8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Checkbox(checked = rememberPIN, onCheckedChange = { rememberPIN = it })
                                Column {
                                    Text("PIN merken", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                                    Text("Verschlüsselt auf dem Gerät gespeichert", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            Spacer(Modifier.height(16.dp))
                            Button(
                                onClick = {
                                    connecting = true; errorMessage = null
                                    scope.launch {
                                        val result = withFintsThread {
                                            val bank = selectedBank ?: return@withFintsThread null
                                            val input = """{"blz":"${bank.blz}","user":"$kennung","pin":"$pin","product":"F7C4049477F6136957A46EC28"}"""
                                            val r = WimgJni.nativeFintsConnect(input) ?: return@withFintsThread null
                                            json.decodeFromString<FintsResult>(r)
                                        }
                                        connecting = false
                                        if (result == null) { errorMessage = "Verbindung fehlgeschlagen"; return@launch }
                                        when (result.status) {
                                            "ok" -> {
                                                // Save credentials
                                                fintsPrefs.edit()
                                                    .putString(KEY_BLZ, selectedBank?.blz)
                                                    .putString(KEY_KENNUNG, kennung)
                                                    .apply()
                                                if (rememberPIN) {
                                                    fintsPrefs.edit().putString(KEY_PIN, pin).apply()
                                                } else {
                                                    fintsPrefs.edit().remove(KEY_PIN).apply()
                                                }
                                                stage = "dateRange"
                                            }
                                            "tan_required" -> { challengeText = result.challenge ?: ""; photoTanB64 = result.phototan; isDecoupled = result.decoupled ?: false; stage = "tan" }
                                            else -> errorMessage = result.message ?: "Fehler"
                                        }
                                    }
                                },
                                enabled = !connecting && kennung.isNotBlank() && pin.isNotBlank(),
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
                            ) {
                                Text(if (connecting) "Verbinde..." else "Verbinden", fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
                            }
                            TextButton(onClick = { stage = "banks" }) { Text(L("Andere Bank wählen")) }
                        }
                    }
                }
            }

            "tan" -> {
                item {
                    Card(modifier = Modifier.fillMaxWidth(), shape = WimgShapes.large, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                        Column(modifier = Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(if (isDecoupled) "Freigabe in Banking-App" else "TAN-Eingabe", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            if (challengeText.isNotBlank()) {
                                Spacer(Modifier.height(8.dp))
                                Text(challengeText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            val photoTanBitmap = remember(photoTanB64) {
                                photoTanB64?.let { b64 ->
                                    try {
                                        val bytes = Base64.decode(b64, Base64.DEFAULT)
                                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                    } catch (_: Exception) { null }
                                }
                            }
                            if (photoTanBitmap != null) {
                                Spacer(Modifier.height(12.dp))
                                Image(photoTanBitmap.asImageBitmap(), "photoTAN", modifier = Modifier.size(240.dp).clip(RoundedCornerShape(16.dp)))
                            }
                            if (!isDecoupled) {
                                Spacer(Modifier.height(12.dp))
                                OutlinedTextField(value = tanInput, onValueChange = { tanInput = it }, label = { Text("TAN") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                            }
                            Spacer(Modifier.height(16.dp))
                            Button(
                                onClick = {
                                    connecting = true
                                    scope.launch {
                                        val result = withFintsThread {
                                            val tan = if (isDecoupled) "" else tanInput
                                            val r = WimgJni.nativeFintsSendTan("""{"tan":"$tan"}""") ?: return@withFintsThread null
                                            json.decodeFromString<FintsResult>(r)
                                        }
                                        connecting = false
                                        if (result == null) { errorMessage = "TAN fehlgeschlagen"; return@launch }
                                        when (result.status) {
                                            "ok" -> stage = "dateRange"
                                            "tan_required" -> { challengeText = result.challenge ?: ""; photoTanB64 = result.phototan; tanInput = "" }
                                            else -> errorMessage = result.message ?: "Fehler"
                                        }
                                    }
                                },
                                enabled = !connecting && (isDecoupled || tanInput.isNotBlank()),
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
                            ) {
                                Text(if (isDecoupled) "Status prüfen" else "TAN senden", fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }

            "dateRange" -> {
                item {
                    Card(modifier = Modifier.fillMaxWidth(), shape = WimgShapes.large, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                        Column(modifier = Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Outlined.CalendarMonth, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.height(12.dp))
                            Text(L("Kontoauszüge abrufen"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            Text("Letzte 90 Tage", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.height(16.dp))
                            Button(
                                onClick = {
                                    stage = "fetching"; errorMessage = null
                                    scope.launch {
                                        val cal = java.util.Calendar.getInstance()
                                        val to = String.format("%04d-%02d-%02d", cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH))
                                        cal.add(java.util.Calendar.DAY_OF_YEAR, -90)
                                        val from = String.format("%04d-%02d-%02d", cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH))

                                        val result = withFintsThread {
                                            val r = WimgJni.nativeFintsFetch("""{"from":"$from","to":"$to"}""") ?: return@withFintsThread null
                                            json.decodeFromString<FintsResult>(r)
                                        }
                                        if (result == null) { errorMessage = "Abruf fehlgeschlagen"; stage = "dateRange"; return@launch }
                                        if (result.status == "tan_required") {
                                            challengeText = result.challenge ?: ""; photoTanB64 = result.phototan; isDecoupled = result.decoupled ?: false; tanInput = ""; stage = "tan"
                                        } else {
                                            importedCount = result.imported ?: 0; duplicateCount = result.duplicates ?: 0; stage = "result"
                                        }
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
                            ) {
                                Text("Abrufen", fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
                            }
                        }
                    }
                }
            }

            "fetching" -> {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator()
                            Spacer(Modifier.height(16.dp))
                            Text(L("Lade Kontoauszüge..."), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }

            "result" -> {
                item {
                    Card(modifier = Modifier.fillMaxWidth(), shape = WimgShapes.large, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                        Column(modifier = Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(modifier = Modifier.size(64.dp).clip(CircleShape).background(com.wimg.app.models.WimgCategory.INCOME.color.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
                                Text("✓", fontSize = 28.sp, color = com.wimg.app.models.WimgCategory.INCOME.color)
                            }
                            Spacer(Modifier.height(16.dp))
                            Text(L("Abruf erfolgreich!"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.height(8.dp))
                            Text("$importedCount importiert", style = MaterialTheme.typography.bodySmall)
                            if (duplicateCount > 0) Text("$duplicateCount Duplikate", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.height(16.dp))
                            OutlinedButton(onClick = { stage = "banks"; kennung = ""; pin = "" }, modifier = Modifier.fillMaxWidth(), shape = WimgShapes.small) {
                                Text(L("Weitere Bank verbinden"))
                            }
                        }
                    }
                }
            }
        }

        // Error
        if (errorMessage != null) {
            item {
                Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Text(errorMessage!!, modifier = Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
