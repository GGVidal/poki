import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.ComposeUIViewController
import platform.Foundation.NSLog

// RAW 76 fixture: every control logs one line and updates the visible "lastEvent" text.
var count = 0
val last = mutableStateOf("0 start")
fun log(e: String) { count++; last.value = "$count $e"; NSLog("FIXLOG %s", "$count $e") }

fun MainViewController() = ComposeUIViewController { App() }

@Composable
fun App() {
    var tab by remember { mutableStateOf(0) }
    var detail by remember { mutableStateOf(false) }
    var on by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    MaterialTheme {
        Scaffold(bottomBar = {
            NavigationBar {
                NavigationBarItem(selected = tab == 0, onClick = { tab = 0; log("tab 0") }, icon = { Text("1") }, label = { Text("ComposeTabOne") })
                NavigationBarItem(selected = tab == 1, onClick = { tab = 1; log("tab 1") }, icon = { Text("2") }, label = { Text("ComposeTabTwo") })
            }
        }) { pad ->
            Column(Modifier.padding(pad).padding(16.dp)) {
                Text("last ${last.value}", Modifier.semantics { testTag = "lastEvent" })
                if (detail) {
                    Text("ComposeDetail")
                    Button(onClick = { log("detail unique button") }) { Text("ComposeDetailButton") }
                    Button(onClick = { detail = false; log("detail back") }) { Text("ComposeBack") }
                } else if (tab == 0) {
                    Button(onClick = { log("button") }) { Text("ComposeButton") }
                    Row(Modifier.fillMaxWidth().clickable { log("row tap"); detail = true }.padding(12.dp)) { Text("ComposeRow") }
                    Row { Text("ComposeSwitch"); Switch(checked = on, onCheckedChange = { on = it; log("switch $it") }) }
                    TextField(value = text, onValueChange = { text = it }, label = { Text("ComposeField") },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { log("field done '$text'") }))
                } else {
                    Text("TabTwoContent")
                }
            }
        }
    }
}
