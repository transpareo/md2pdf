# Runtime image with Chromium already present, for CI and for anyone
# who would rather not install a browser on the host.
#
#   docker build -t transpareo-md2pdf .
#   docker run --rm -v "$PWD:/work" transpareo-md2pdf doc.md
FROM ruby:3.3-slim

# Chromium plus the fonts it needs to lay text out sensibly. Without
# a font package the PDF renders in fallback glyphs.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       chromium \
       fonts-dejavu-core \
       fonts-liberation \
       ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV CHROMIUM=/usr/bin/chromium

WORKDIR /gem
COPY . .
RUN gem build transpareo-md2pdf.gemspec \
  && gem install ./transpareo-md2pdf-*.gem \
  && rm -f ./transpareo-md2pdf-*.gem

WORKDIR /work
ENTRYPOINT ["md2pdf"]
CMD ["--help"]
