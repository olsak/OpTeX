.POSIX:
.SUFFIXES:

NAME = omls
VERSION = 0.1.0
REVISION = 1

ROCKSPEC = $(NAME)-$(VERSION)-$(REVISION).rockspec
DIST = $(NAME)-$(VERSION).zip

all: $(DIST) $(ROCKSPEC)

$(DIST):
	mkdir -p "$(NAME)-$(VERSION)"
	cp -a src "$(NAME)-$(VERSION)"
	zip -qrD $@ "$(NAME)-$(VERSION)"
	rm -rf "$(NAME)-$(VERSION)"

$(ROCKSPEC): rockspec.in
	sed -e "s/@NAME@/$(NAME)/g; s/@VERSION@/$(VERSION)/g; s/@REVISION@/$(REVISION)/g" $< > $@

clean:
	rm -f $(DIST) $(ROCKSPEC)
