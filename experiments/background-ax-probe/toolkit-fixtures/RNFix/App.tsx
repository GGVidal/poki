// RAW 76 fixture: every control logs one line and updates the visible "lastEvent" text.
import React, {useSyncExternalStore, useState} from 'react';
import {View, Text, Pressable, Switch, FlatList, TextInput, NativeModules} from 'react-native';
import {NavigationContainer} from '@react-navigation/native';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';

let count = 0;
let last = '0 start';
const subs = new Set<() => void>();
function log(e: string) { count++; last = `${count} ${e}`; console.log(`FIXLOG ${last}`); subs.forEach(f => f()); }
function useLast() { return useSyncExternalStore(cb => { subs.add(cb); return () => subs.delete(cb); }, () => last); }
const Last = () => { const v = useLast(); return <Text testID="lastEvent" accessibilityLabel={`last ${v}`}>last {v}</Text>; };

const Stack = createNativeStackNavigator();
const Tab = createBottomTabNavigator();

function Home({navigation}: any) {
  const [on, setOn] = useState(false);
  return (
    <View style={{padding: 16, gap: 8}}>
      <Last />
      <Pressable accessibilityRole="button" accessibilityLabel="RNPress" testID="press.plain" onPress={() => log('press plain')}><Text>RNPress A</Text></Pressable>
      <Pressable accessibilityRole="button" accessibilityLabel="RNPress" testID="press.tap" onPress={() => log('press tap-variant onPress')} onAccessibilityTap={() => log('press onAccessibilityTap')}><Text>RNPress B</Text></Pressable>
      <Pressable accessibilityRole="button" accessibilityLabel="RNPress" testID="press.action" accessibilityActions={[{name: 'activate'}]} onAccessibilityAction={e => log(`press action ${e.nativeEvent.actionName}`)} onPress={() => log('press action-variant onPress')}><Text>RNPress C</Text></Pressable>
      <Switch accessibilityLabel="RNSwitch" value={on} onValueChange={v => { setOn(v); log(`switch ${v}`); }} />
      <TextInput accessibilityLabel="RNField" placeholder="RNField" onSubmitEditing={e => log(`field submitted '${e.nativeEvent.text}'`)} style={{borderWidth: 1, padding: 8}} />
      <FlatList data={[{k: 'RNRow'}]} keyExtractor={i => i.k} renderItem={({item}) => (
        <Pressable accessibilityRole="button" accessibilityLabel={item.k} onPress={() => { log('row tap'); navigation.navigate('Detail'); }}><Text>{item.k}</Text></Pressable>)} />
    </View>);
}
function Detail() {
  return (<View style={{padding: 16}}><Last /><Pressable accessibilityRole="button" accessibilityLabel="RNDetailButton" onPress={() => log('detail unique button')}><Text>RNDetailButton</Text></Pressable></View>);
}
function TabOne() {
  return (<Stack.Navigator><Stack.Screen name="Home" component={Home} /><Stack.Screen name="Detail" component={Detail} /></Stack.Navigator>);
}
function TabTwo() { return (<View style={{padding: 16}}><Last /><Text>TabTwoContent</Text></View>); }
export default function App() {
  return (
    <NavigationContainer>
      <Tab.Navigator screenListeners={{tabPress: e => log(`tab ${e.target?.split('-')[0]}`)}}>
        <Tab.Screen name="RNTabOne" component={TabOne} options={{headerShown: false}} />
        <Tab.Screen name="RNTabTwo" component={TabTwo} />
      </Tab.Navigator>
    </NavigationContainer>);
}
