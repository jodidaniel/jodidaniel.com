# frozen_string_literal: true

# Sets the link-preview picture from `_data/settings.yml` (`share.image` and
# `share.image_alt`), so the owner picks it in /admin (Site Settings) instead of
# it being baked into `_config.yml`.
#
# It becomes `page.image` on the home page and on every media page. jekyll-seo-tag
# reads `page.image` for og:image / twitter:image on the home page, and
# _layouts/media.html reads it in its hand-written head.
#
# ONLY WHILE THE SITE IS LIVE. With `site_live` false nothing is set, so the
# coming-soon page and the gated media pages carry no picture: the default
# card holds her headshot, which is not cleared for the coming-soon page. The
# layouts' gated arms print no image either; this is the second lock.
#
# A blank field, a path that is not site-relative, or a file that is not in the
# site leaves the image unset, so a preview is never pointed at a missing file.
# Width and height are read from a PNG's header so first-time shares render
# at once; other formats go without them.
#
# Unit tests: scripts/test-share-image.rb

module JodiShareImage
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  # Pure data shaping, kept Jekyll-free so the unit tests need no site build.
  # `exists` answers whether a site-relative path is a file in the source.
  # `png_size` returns [width, height] for a site-relative path, or nil.
  def self.image(settings, exists:, png_size:)
    return nil unless settings.is_a?(Hash) && settings["site_live"] == true

    share = settings["share"]
    return nil unless share.is_a?(Hash)

    path = share["image"]
    return nil unless path.is_a?(String) && path.start_with?("/") && !path.include?("..")
    return nil unless exists.call(path)

    image = { "path" => path }
    alt = share["image_alt"]
    image["alt"] = alt.strip if alt.is_a?(String) && !alt.strip.empty?
    size = png_size.call(path)
    image["width"], image["height"] = size if size
    image
  end

  def self.png_size(file)
    header = File.binread(file, 24)
    return nil unless header && header.bytesize == 24 && header.start_with?(PNG_SIGNATURE)

    header[16, 8].unpack("NN")
  rescue SystemCallError
    nil
  end
end

Jekyll::Hooks.register :site, :post_read do |site|
  source = ->(path) { File.join(site.source, path.delete_prefix("/")) }
  image = JodiShareImage.image(
    site.data["settings"],
    exists: ->(path) { File.file?(source.call(path)) },
    png_size: ->(path) { JodiShareImage.png_size(source.call(path)) }
  )
  next unless image

  pages = site.pages.select { |page| page.data["layout"] == "home" }
  media = site.collections["media"]&.docs || []
  (pages + media).each { |doc| doc.data["image"] = image.dup }
end
