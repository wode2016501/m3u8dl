# Makefile - 最终稳定版（生成可直接并行的 ts_download.mk）
M3U8_URL   ?=
LOCAL_PLAYLIST ?= playlist.m3u8
THREADS    ?= 8

TS_DIR   = ts
KEYS_DIR = keys
RAW_M3U8 = raw.m3u8
TS_MAKEFILE = ts_download.mk
KEY_URL  = key_url.txt

CURL   = wget -o /dev/null -c -O
MKDIR  = mkdir -p
RM     = rm -f
RMDIR  = rm -rf
SED    = sed
GREP   = grep
MV     = mv
TEST   = test

.PHONY: all clean

all: $(LOCAL_PLAYLIST) download_ts

$(RAW_M3U8):
	$(TEST) -n "$(M3U8_URL)" || (echo "错误: M3U8_URL 未设置" && exit 1)
	@echo "下载播放列表..."
	$(CURL) $@ "$(M3U8_URL)"

$(KEY_URL): $(RAW_M3U8)
	@$(RM) $@
	@domain=$$(echo "$(M3U8_URL)" | $(SED) -E 's|^(https?://[^/]+).*$$|\1|'); \
	dir=$$(dirname "$(M3U8_URL)")/; \
	uri=$$($(GREP) -oP 'URI="\K[^"]+' $(RAW_M3U8) | head -1); \
	if [ -n "$$uri" ]; then \
		case "$$uri" in \
			http://*|https://*) echo "$$uri" ;; \
			/*) echo "$$domain$$uri" ;; \
			*) echo "$$dir$$uri" ;; \
		esac; \
	fi > $@

download_key: $(KEY_URL) | $(KEYS_DIR)
	@if [ -s $(KEY_URL) ]; then \
		key_url=$$(cat $(KEY_URL)); \
		key_file=$$(basename "$$key_url" | $(SED) 's/?.*//'); \
		if [ ! -f "$(KEYS_DIR)/$$key_file" ]; then \
			echo "下载密钥..."; \
			$(CURL) "$(KEYS_DIR)/$$key_file" "$$key_url"; \
		fi; \
	fi

$(LOCAL_PLAYLIST): $(RAW_M3U8) download_key | $(TS_DIR)
	@echo "生成播放列表..."
	@cp $(RAW_M3U8) $@.tmp
	@$(SED) -i 's/\r$$//' $@.tmp
	@if [ -s $(KEY_URL) ]; then \
		key_url=$$(cat $(KEY_URL)); \
		key_file=$$(basename "$$key_url" | $(SED) 's/?.*//'); \
		$(SED) -i 's|URI="[^"]*"|URI="$(KEYS_DIR)/'"$$key_file"'"|' $@.tmp; \
	fi
	@$(SED) -i -E '/^[^#]/ s|^|ts/|' $@.tmp
	@$(SED) -i -E '/^[^#]/ s|.*/([^/?]+)(\?.*)?$$|$(TS_DIR)/\1|' $@.tmp
	@$(MV) $@.tmp $@

$(TS_MAKEFILE): $(RAW_M3U8) | $(TS_DIR)
	@echo "生成 $(TS_MAKEFILE)..."
	@$(RM) $@
	@domain=$$(echo "$(M3U8_URL)" | $(SED) -E 's|^(https?://[^/]+).*$$|\1|'); \
	dir=$$(dirname "$(M3U8_URL)")/; \
	{ \
		echo "# 自动生成"; \
		echo "TS_DIR = $(TS_DIR)"; \
		echo "CURL = $(CURL)"; \
		echo "MV = $(MV)"; \
		echo "MKDIR = $(MKDIR)"; \
		echo ".PHONY: all_ts"; \
		echo -n "all_ts: \$$(TS_DIR) "; \
		$(GREP) -v '^#' $(RAW_M3U8) | $(GREP) '\.ts' | $(SED) 's/\r$$//' | while read line; do \
			case "$$line" in \
				http://*|https://*) url="$$line";; \
				/*) url="$$domain$$line";; \
				*) url="$$dir$$line";; \
			esac; \
			fname=$$(basename "$$url" | $(SED) 's/?.*//'); \
			echo -n "\$$(TS_DIR)/$$fname "; \
		done; \
		echo ""; \
		echo ""; \
		echo "\$$(TS_DIR):"; \
		echo "	\$$(MKDIR) \$$(TS_DIR)"; \
		echo ""; \
		$(GREP) -v '^#' $(RAW_M3U8)  | $(SED) 's/\r$$//' | while read line; do \
			case "$$line" in \
				http://*|https://*) url="$$line";; \
				/*) url="$$domain$$line";; \
				*) url="$$dir$$line";; \
			esac; \
			fname=$$(basename "$$url" | $(SED) 's/?.*//'); \
			echo "\$$(TS_DIR)/$$fname: | \$$(TS_DIR)"; \
			echo "	@echo \"下载 $$fname\""; \
			echo "	while sleep 1;do \$$(CURL) \"\$$@.tmp\" \"$$url\" && \$$(MV) \"\$$@.tmp\" \"\$$@\" && break ;done"; \
			echo ""; \
		done; \
	} > $@
	@echo "生成完成，共 $$(grep -c '\.ts' $(RAW_M3U8)) 个片段"

download_ts: $(TS_MAKEFILE)
	@echo "并行下载 TS（$(THREADS) 线程）..."
	@$(MAKE) -f $(TS_MAKEFILE)  all_ts

$(TS_DIR):
	$(MKDIR) $@
$(KEYS_DIR):
	$(MKDIR) $@

clean:
	$(RM) $(RAW_M3U8) $(KEY_URL) $(TS_MAKEFILE) $(LOCAL_PLAYLIST)
	$(RMDIR) $(TS_DIR) $(KEYS_DIR) 2>/dev/null || true