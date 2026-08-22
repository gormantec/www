import React from 'react';
import { View, Text, StyleSheet, ScrollView } from 'react-native';
import Checkbox from 'expo-checkbox';
import { StatusBar } from 'expo-status-bar';
import {
  Appbar,
  Button as PaperButton,
  Card,
  Divider,
  PaperProvider,
} from 'react-native-paper';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
import StatusPill from './StatusPill';

const APP_BAR_HEIGHT = 56;

function Screen() {
  const insets = useSafeAreaInsets();

  return (
    <View style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.scaffold}>
        <Appbar.Header mode="small" statusBarHeight={insets.top} style={styles.appBar}>
          <Appbar.Content title="Snack SDK Demo" subtitle="Scaffold + App Bar" />
          <Appbar.Action icon="refresh" onPress={() => {}} />
        </Appbar.Header>

        <ScrollView contentContainerStyle={styles.content}>
          <Card style={styles.card} mode="outlined">
            <Card.Content>
              <Text style={styles.title}>Updated from Snack SDK</Text>
              <Text style={styles.sub}>Updated at ##TIMESTAMP##</Text>
              <StatusPill label="Dependency widget test active" />
            </Card.Content>
          </Card>

          <InteractiveSection />
        </ScrollView>
      </View>
    </View>
  );
}

function InteractiveSection() {
  const [checked, setChecked] = React.useState(false);

  return (
    <Card style={styles.card} mode="outlined">
      <Card.Content>
        <Text style={styles.sectionTitle}>Interactive controls</Text>
        <Divider style={styles.divider} />
        <View style={styles.checkboxRow}>
          <Checkbox value={checked} onValueChange={setChecked} color={checked ? '#0b73d9' : undefined} />
          <Text style={styles.checkLabel}>{checked ? 'Checkbox checked' : 'Checkbox unchecked'}</Text>
        </View>
        <View style={styles.paperWrap}>
          <Text style={styles.paperLabel}>react-native-paper dependency:</Text>
          <PaperButton mode="contained" onPress={() => setChecked((value) => !value)}>
            Toggle checkbox state
          </PaperButton>
        </View>
      </Card.Content>
    </Card>
  );
}


export default function App() {
  return (
    <PaperProvider>
      <SafeAreaProvider>
        <Screen />
      </SafeAreaProvider>
    </PaperProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#eef8ff' },
  scaffold: { flex: 1 },
  appBar: { backgroundColor: '#0b73d9', minHeight: APP_BAR_HEIGHT },
  content: { padding: 14, gap: 12 },
  card: {
    borderRadius: 14,
    backgroundColor: '#ffffff',
    borderColor: '#c9d9ea',
  },
  title: { fontSize: 24, fontWeight: '700', color: '#0b73d9', marginBottom: 8 },
  sub: { fontSize: 15, color: '#3f4c60' },
  sectionTitle: { fontSize: 18, fontWeight: '600', color: '#22364f' },
  divider: { marginTop: 8, marginBottom: 10 },
  checkboxRow: { marginTop: 14, flexDirection: 'row', alignItems: 'center' },
  checkLabel: { marginLeft: 10, fontSize: 15, color: '#304255' },
  paperWrap: { marginTop: 14 },
  paperLabel: { fontSize: 14, color: '#304255', marginBottom: 8 },
});