import 'dart:ui' show Offset;

/// Pilih display target untuk layar penonton — fungsi MURNI (tanpa
/// dependensi package screen_retriever) supaya gampang dites.
///
/// Input: [positions] = visiblePosition tiap display dari
/// screen_retriever (null bila posisinya tidak diketahui).
///
/// Aturan (definisi "non-utama" dari posisi, bukan dari urutan):
/// - Display utama Windows SELALU di Offset.zero (0,0); display kedua
///   bergeser, mis. (1920,0) bila TV di kanan atau (-1920,0) bila di kiri.
///   Jadi target = display PERTAMA yang posisinya bukan (0,0).
/// - Bila semua posisi (0,0) (mode Duplicate/mirroring: semua display
///   menumpuk di titik yang sama) -> indeks 1 bila ada, else 0. Di mode
///   ini pindah tidak ada artinya (semua tampil sama), tapi indeks 1
///   dipilih agar perilaku konsisten dengan "monitor kedua".
/// - Satu display -> 0. List kosong -> null.
///
/// CATATAN JUJUR: bila TV diset sebagai display UTAMA di Windows
/// (TV di (0,0), laptop di (1920,0)), target = laptop (display
/// non-utama). Itu benar menurut definisi "bukan utama", tapi artinya
/// penonton mendarat di laptop — bukan di TV. Kasus ini TIDAK
/// disembunyikan: laporan display ke operator menampilkan indeks +
/// posisi target, jadi operator bisa melihatnya dan menukar display
/// utama di Settings Windows bila perlu.
///
/// Posisi null diperlakukan seperti (0,0): posisi yang tidak diketahui
/// tidak boleh dianggap terbukti non-utama (kita tidak bisa pindah ke
/// posisi yang tidak kita ketahui).
int? pickDisplayTarget(List<Offset?> positions) {
  if (positions.isEmpty) return null;
  for (var i = 0; i < positions.length; i++) {
    final pos = positions[i];
    if (pos != null && pos != Offset.zero) return i;
  }
  return positions.length > 1 ? 1 : 0;
}
