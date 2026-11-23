import 'package:flutter/material.dart';

// RAW 76 fixture: every control logs one line and updates the visible "lastEvent" label.
int count = 0;
final ValueNotifier<String> last = ValueNotifier('0 start');
void log(String e) { count++; last.value = '$count $e'; debugPrint('FIXLOG $count $e'); }

void main() => runApp(const MaterialApp(home: Home()));

class LastLabel extends StatelessWidget {
  const LastLabel({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
      valueListenable: last,
      builder: (_, v, __) => Semantics(identifier: 'lastEvent', label: 'last $v', child: Text('last $v')));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  bool on = false;
  @override
  Widget build(BuildContext context) {
    final page0 = ListView(children: [
      const LastLabel(),
      ListTile(title: const Text('FlutterRow'), onTap: () { log('row tap'); Navigator.push(context, MaterialPageRoute(builder: (_) => const Detail())); }),
      ElevatedButton(onPressed: () => log('elevated button'), child: const Text('FlutterButton')),
      SwitchListTile(title: const Text('FlutterSwitch'), value: on, onChanged: (v) { setState(() => on = v); log('switch $v'); }),
      TextField(decoration: const InputDecoration(labelText: 'FlutterField'), onSubmitted: (t) => log("field submitted '$t'")),
    ]);
    final page1 = const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [LastLabel(), Text('TabTwoContent')]));
    return Scaffold(
      appBar: AppBar(title: const Text('FlutterFix')),
      body: tab == 0 ? page0 : page1,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        onTap: (i) { setState(() => tab = i); log('tab $i'); },
        items: const [BottomNavigationBarItem(icon: Icon(Icons.home), label: 'TabOne'), BottomNavigationBarItem(icon: Icon(Icons.star), label: 'TabTwo')],
      ),
    );
  }
}

class Detail extends StatelessWidget {
  const Detail({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('FlutterDetail')),
      body: Column(children: [const LastLabel(), ElevatedButton(onPressed: () => log('detail unique button'), child: const Text('FlutterDetailButton'))]));
}
