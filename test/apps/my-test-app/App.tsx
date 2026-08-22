import React from 'react';
import { SafeAreaView, View, Text, StyleSheet } from 'react-native';
import Checkbox from 'expo-checkbox';
import { Button as PaperButton } from 'react-native-paper';
import StatusPill from './StatusPill';


export default function App() {
  const [checked, setChecked] = React.useState(false);

  return (
    <SafeAreaView style={styles.root}>
      <View style={styles.card}>
        <Text style={styles.title}>Updated from Snack SDK</Text>
        <Text style={styles.sub}>Updated at ##TIMESTAMP##</Text>
        <StatusPill label="Dependency widget test active" />
        <View style={styles.checkboxRow}>
          <Checkbox value={checked} onValueChange={setChecked} color={checked ? '#0b73d9' : undefined} />
          <Text style={styles.checkLabel}>{checked ? 'Checkbox checked' : 'Checkbox unchecked'}</Text>
        </View>
        <View style={styles.paperWrap}>
          <Text style={styles.paperLabel}>react-native-paper dependency:</Text>
          <PaperButton mode="contained" onPress={() => {}}>
            Paper button ready
          </PaperButton>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#eef8ff' },
  card: { width: 320, borderRadius: 14, padding: 20, backgroundColor: '#ffffff', borderWidth: 1, borderColor: '#c9d9ea' },
  title: { fontSize: 26, fontWeight: '700', color: '#0b73d9', marginBottom: 8 },
  sub: { fontSize: 16, color: '#3f4c60' },
  checkboxRow: { marginTop: 14, flexDirection: 'row', alignItems: 'center' },
  checkLabel: { marginLeft: 10, fontSize: 15, color: '#304255' },
  paperWrap: { marginTop: 14 },
  paperLabel: { fontSize: 14, color: '#304255', marginBottom: 8 },
});