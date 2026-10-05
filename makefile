include module.spec
-include .env

BUILD_DIR ?= build
REL = $(BUILD_DIR)/rel
PANEL = $(REL)/panel
SERVER = $(REL)/server
MODULE_PANEL = $(PANEL)/mod_transport
MODULE_SERVER = $(SERVER)/mod_transport

ERL_INCLUDE_DIRS = \
	-I $(ERL_ROOT)/ejabberd-0.0/include \
	-I $(ERL_ROOT)/xmpp-1.1.20/include \
	-I $(ERL_ROOT)/fast_xml-1.1.54/include

.PHONY: all archive check-env mkdirs compile copy clean

all: archive

check-env:
	@test -n "$(ERL_ROOT)" || (echo "ERL_ROOT is not set. Copy .env.example to .env and adjust local paths." >&2; exit 1)
	@test -n "$(ERLC)" || (echo "ERLC is not set. Copy .env.example to .env and adjust local paths." >&2; exit 1)
	@test -n "$(ERL_NATIVE_LIB_DIR)" || (echo "ERL_NATIVE_LIB_DIR is not set. Copy .env.example to .env and adjust local paths." >&2; exit 1)

mkdirs:
	@mkdir -p $(PANEL)
	@mkdir -p $(SERVER)
	@mkdir -p server/mod_transport/ebin

compile: check-env mkdirs
	@echo -n "Compile Erlang ..."
	@LD_LIBRARY_PATH=$(ERL_NATIVE_LIB_DIR):$(LD_LIBRARY_PATH) $(ERLC) $(ERLC_FLAGS) $(ERL_INCLUDE_DIRS) -o server/mod_transport/ebin server/mod_transport/src/mod_transport.erl
	@echo ". done."

copy: compile
	@rm -rf $(MODULE_PANEL) $(MODULE_SERVER)
	@cp -r module.spec $(REL)/ && echo -n "."
	@cp -r mod_transport $(PANEL)/ && echo -n "."
	@cp -r server/mod_transport $(SERVER)/ && echo -n "."
	@find $(REL) -type d -name __pycache__ -prune -exec rm -rf {} \;
	@find $(REL) -type f -name "*.pyc" -delete

archive: mkdirs copy
	@echo -n "Make archive ..."
	@cd $(REL) && tar -czf "../module_$(NAME)_$(VERSION).tar.gz" panel server module.spec
	@echo ". done."

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f server/mod_transport/ebin/*.beam
