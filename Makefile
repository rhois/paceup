# PaceUp — perintah umum
.PHONY: help setup run demo test check web clean db-schema db-rls db-functions db-seed

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## /  \t/' | sort

setup: ## Ambil dependensi
	flutter pub get

run: ## Jalankan dengan Supabase (butuh SUPABASE_URL & SUPABASE_ANON_KEY)
	flutter run \
	  --dart-define=SUPABASE_URL=$(SUPABASE_URL) \
	  --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY)

demo: ## Jalankan mode lokal/demo (tanpa backend)
	flutter run

test: ## Jalankan semua test
	flutter test

check: ## Analisis + test
	flutter analyze
	flutter test

web: ## Build untuk web
	flutter build web --release

clean: ## Bersihkan artefak build
	flutter clean && flutter pub get

# --- Database (butuh psql + DATABASE_URL) ---
db-schema: ## Terapkan skema
	psql "$(DATABASE_URL)" -v ON_ERROR_STOP=1 -f sql/schema.sql

db-rls: ## Terapkan RLS
	psql "$(DATABASE_URL)" -v ON_ERROR_STOP=1 -f sql/rls.sql

db-functions: ## Terapkan fungsi RPC
	psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/functions.sql

db-seed: ## Isi data contoh (EMAIL=kamu@contoh.com)
	psql "$(DATABASE_URL)" -v ON_ERROR_STOP=1 -v email="$(EMAIL)" -f sql/seed.sql

db-all: db-schema db-rls db-functions ## Skema + RLS + fungsi

# --- APK dari GitHub Actions (tanpa perlu Android SDK lokal) ---
apk: ## Unduh APK terbaru dari GitHub Actions
	@rm -rf /tmp/paceup-apk && mkdir -p /tmp/paceup-apk
	gh run download -R rois-etalas/paceup -n paceup-apk -D /tmp/paceup-apk
	@find /tmp/paceup-apk -name '*.apk' -exec cp {} ./paceup-latest.apk \;
	@echo "APK tersimpan: paceup-latest.apk"
	@ls -lh paceup-latest.apk

install-apk: apk ## Pasang APK ke ponsel yang tersambung USB
	adb install -r paceup-latest.apk

ci: ## Lihat status workflow terakhir
	gh run list -R rois-etalas/paceup --limit 5
