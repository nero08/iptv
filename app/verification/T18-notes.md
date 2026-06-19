# Task 18 (Settings) verification notes
- Settings screen verified on emulator: shows "Appareils utilisés — 2 / 3
  appareils sur ce compte" (real device_count/max from the last redeem), the
  admin-management note, entry points (Profils, Favoris, Sources IPTV,
  Téléchargements), and Déconnexion. (content-descs in /tmp/uset2.xml.)
- Logout preserves device_id: asserted by auth_controller_test ('logout clears
  the stored code' keeps device_id) and confirmed in Tasks 5/9 where re-login
  did not increment the device count (stayed 1/2).
