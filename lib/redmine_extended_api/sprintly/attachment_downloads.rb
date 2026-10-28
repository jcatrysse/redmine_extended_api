# frozen_string_literal: true

module RedmineExtendedApi
  module Sprintly
    # SPR-540: attachments a browser would render as a document are served as opaque bytes.
    #
    # Redmine already sends every download with `Content-Disposition: attachment` and
    # `Content-Security-Policy: sandbox`, which makes a direct visit harmless. The Sprintly SPA
    # does not visit: it fetches the bytes with a Bearer token and opens them as a `blob:` URL
    # of its own origin, where neither header applies — an SVG, HTML or XML file opened that way
    # runs its script as the tracker. The SPA now types its blobs from an allowlist; answering
    # with `application/octet-stream` here covers the clients that still trust the response
    # (SPA tabs opened before the fix, anything else built on the API).
    #
    # The upload itself is untouched — the file keeps its name and stored content type, and is
    # still downloaded byte for byte.
    module AttachmentDownloads
      OPAQUE = 'application/octet-stream'

      # Types a browser renders as a document (and so runs scripts in): HTML, SVG, any XML
      # (`*/xml`, `*+xml`), XSL, and the multipart/MHTML archive formats.
      ACTIVE = %r{\A(?:text/html|text/xsl|[\w.+-]+/(?:[\w.-]+\+)?xml|multipart/[\w.+-]+|message/rfc822)\z}i

      def self.active?(content_type)
        ACTIVE.match?(content_type.to_s.split(';').first.to_s.strip)
      end

      module ControllerPatch
        private

        def detect_content_type(attachment, is_thumb = false)
          type = super
          AttachmentDownloads.active?(type) ? AttachmentDownloads::OPAQUE : type
        end
      end
    end
  end
end
