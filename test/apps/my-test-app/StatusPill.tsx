import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function StatusPill({ label }: { label: string }) {
  return (
    <View style={styles.pill}>
      <Text style={styles.pillText}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  pill: {
    marginTop: 14,
    alignSelf: 'flex-start',
    backgroundColor: '#e8f1fb',
    borderColor: '#a7c7eb',
    borderWidth: 1,
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderRadius: 999,
  },
  pillText: {
    color: '#225f99',
    fontSize: 12,
    fontWeight: '600',
  },
});
