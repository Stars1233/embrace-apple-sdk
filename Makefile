# Taken and modified from KSCrash: https://github.com/kstenerud/KSCrash
#
# Directories to search
SEARCH_DIRS = Sources Tests Examples
SWIFT_SEARCH_DIRS = Sources Tests Examples

# File extensions to format
FILE_EXTENSIONS = c cpp h m mm

# Check for clang-format-18 first, then fall back to clang-format
# brew install clang-format
CLANG_FORMAT := $(shell command -v clang-format-18 2> /dev/null || command -v clang-format 2> /dev/null)

# Swift format command (using toolchain)
# brew install swift-format
SWIFT_FORMAT_CMD = swift format
SWIFT_LINT_CMD=swiftlint

# Define the default target
.PHONY: format check-format swift-format check-swift-format lint check-lint

all: format swift-format lint

format:
ifeq ($(CLANG_FORMAT),)
	@echo "Error: clang-format or clang-format-18 is not installed. Please install it and try again."
	@exit 1
else
	@echo "Using $(CLANG_FORMAT)"
	find $(SEARCH_DIRS) $(foreach ext,$(FILE_EXTENSIONS),-name '*.$(ext)' -o) -false | \
	xargs -r $(CLANG_FORMAT) -style=file -i
endif

check-format:
ifeq ($(CLANG_FORMAT),)
	@echo "Error: clang-format or clang-format-18 is not installed. Please install it and try again."
	@exit 1
else
	@echo "Checking format using $(CLANG_FORMAT)"
	@find $(SEARCH_DIRS) $(foreach ext,$(FILE_EXTENSIONS),-name '*.$(ext)' -o) -false | \
	xargs -r $(CLANG_FORMAT) -style=file -n -Werror
endif

swift-format:
	@echo "Formatting Swift files..."
	@{ find $(SWIFT_SEARCH_DIRS) -name '*.swift' -type f -not -path '*/.build/*'; \
	   [ -f Package.swift ] && echo Package.swift; } | \
	while read file; do \
		$(SWIFT_FORMAT_CMD) format --in-place --configuration .swift-format "$$file"; \
	done

check-swift-format:
	@echo "Checking Swift format..."
	@{ find $(SWIFT_SEARCH_DIRS) -name '*.swift' -type f -not -path '*/.build/*'; \
	   [ -f Package.swift ] && echo Package.swift; } | \
	while read file; do \
		$(SWIFT_FORMAT_CMD) lint --configuration .swift-format "$$file" --strict || exit 1; \
	done

check-lint:
	@echo "Linting Swift files..."
	$(SWIFT_LINT_CMD) lint --quiet --strict --config .swiftlint.yml --force-exclude

lint:
	@echo "Linting Swift files..."
	$(SWIFT_LINT_CMD) lint --fix --progress --config .swiftlint.yml --force-exclude