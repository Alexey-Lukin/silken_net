#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Field frame → the copy that may enter the tree: optional crop, every metadata block dropped, and the
# written file re-read byte by byte before it is called clean. Home of the rule — sheet
# docs/protocols/ebfc/stem_face_winter_light.md §4 «У дерево» (⚖️ founder 2026-11-15, 00_07 HW.54).
#
#   bundle exec ruby scripts/strip_frame.rb IN OUT [--crop X,Y,W,H] [--force]
#   bundle exec ruby scripts/strip_frame.rb --check FILE
#   bundle exec ruby scripts/strip_frame.rb --selftest
#
# IN — anything libvips loads: JPEG; HEIC when libvips is built with libheif (Homebrew vips is). OUT — .jpg or .png.
# An OUT that exists is refused (--force replaces it; an OUT that IS the input — BIG.JPG ⇄ big.jpg on APFS, a hard
# link — is refused always). X,Y — the top-left corner, W,H — the size, in pixels of the frame as shown (after the
# EXIF rotation). Without coordinates: crop a DUPLICATE in Preview (Tools → Crop, ⌘K), save it, run this without
# --crop — Preview keeps the metadata, this strips it.
# Order: rotate by the EXIF orientation → crop → an embedded ICC profile converted to sRGB (colours stay; the
# profile, which names the device maker, goes) → save with keep: none to a temporary file beside OUT. On
# libvips ≥ 8.15 that is the switch SEC.18 sets on maintenance thumbnails under its older name `saver: { strip: true }`
# (app/models/maintenance_record.rb); an older libvips has no `keep`, and the run is refused before writing →
# the file re-read by a byte walk that does not use libvips: JPEG — every marker, nothing after EOI; PNG — every
# chunk. Anything outside the allowlist (JPEG APP1–APP15, COM, an APP0 other than a 16-byte thumbnail-free JFIF;
# PNG — anything but IHDR · PLTE · IDAT · IEND · a 9-byte pHYs) → the temporary file deleted, OUT not created,
# exit 1; clean → renamed to OUT. --check runs the same walk on a file, but it judges block TYPES (and the APP0 and
# pHYs lengths), not the bytes inside the JPEG tables nor a PNG CRC: it vouches for THIS command's output, not for
# an arbitrary file.
#
# Declared ceiling — what a green run does NOT prove:
#   · pixels are not judged: a house number, a face or a car plate INSIDE the crop stays — the crop is the lever;
#   · JPEG output is re-encoded (Q 95) and loses detail; PNG does not — for a thin layer of snow, prefer PNG;
#   · HEIC is tested on files written by libvips and by macOS sips, not on an iPhone frame (tiles, 10 bit) — run
#     --check on the first real output;
#   · a HEIC on a machine whose libvips lacks libheif fails to load — the error names the fallback: convert first
#     with macOS `sips -s format jpeg IN.HEIC --out IN.jpg` (sips keeps the metadata; this script still strips it),
#     or shoot JPEG (iPhone: Settings → Camera → Formats → Most Compatible);
#   · where the originals live outside the repo is not decided here (00_07 HW.54).

require "vips"
require "tmpdir"

module StripFrame
  JPEG_TABLES = [ *0xC0..0xCF, 0xDB, 0xDD, 0xDA ].freeze # SOFn · DHT · DAC · DQT · DRI · SOS
  PNG_ALLOWED = %w[IHDR PLTE IDAT IEND pHYs].freeze # what libvips writes with keep: none — nothing more

  module_function

  # [[label, allowed?], …] for every block of the file, in order.
  def audit(path)
    bytes = File.binread(path)
    return png_blocks(bytes) if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
    return jpeg_blocks(bytes) if bytes.start_with?("\xFF\xD8".b)

    [ [ "not a JPEG/PNG", false ] ]
  end

  def jpeg_blocks(bytes)
    out = [ [ "SOI", true ] ]
    i = 2
    while i < bytes.bytesize
      return out << [ "garbage at #{i}", false ] unless bytes.getbyte(i) == 0xFF

      m = bytes.getbyte(i + 1)
      return out << [ "truncated at #{i}", false ] if m.nil?

      if m == 0xFF # fill byte: the marker starts at the next 0xFF
        i += 1
        next
      end
      i += 2
      if m == 0xD9
        trailing = bytes.bytesize - i
        out << [ "EOI", true ]
        out << [ "#{trailing} B after EOI", false ] if trailing.positive?
        return out
      end
      raw = bytes.byteslice(i, 2)
      len = raw&.bytesize == 2 ? raw.unpack1("n") : 0
      return out << [ "truncated at #{i}", false ] if len < 2 || i + len > bytes.bytesize

      seg = bytes.byteslice(i + 2, len - 2).to_s
      out << jpeg_label(m, seg)
      i += len
      next unless m == 0xDA

      # entropy-coded data: 0xFF is stuffed (FF00) or a restart (FFD0–D7); any other FFxx is the next marker
      i += 1 until i + 1 >= bytes.bytesize ||
                   (bytes.getbyte(i) == 0xFF && ![ 0x00, *0xD0..0xD7 ].include?(bytes.getbyte(i + 1)))
    end
    out << [ "no EOI", false ]
  end

  def jpeg_label(marker, seg)
    tag = seg[/\A[\x20-\x7E]{1,40}/n].to_s
    case marker
    when 0xE0 then [ "APP0 #{tag}", tag == "JFIF" && seg.bytesize == 14 && seg.getbyte(12).zero? && seg.getbyte(13).zero? ]
    when 0xE1..0xEF then [ "APP#{marker - 0xE0} #{tag}".strip, false ]
    when 0xFE then [ "COM", false ]
    else [ format("FF%02X", marker), JPEG_TABLES.include?(marker) ]
    end
  end

  def png_blocks(bytes)
    out = []
    i = 8
    while i + 8 <= bytes.bytesize
      len, type = bytes.byteslice(i, 8).unpack("Na4")
      return out << [ "truncated #{type}", false ] if i + 12 + len > bytes.bytesize

      out << [ type, PNG_ALLOWED.include?(type) && (type != "pHYs" || len == 9) ]
      i += 12 + len
      return out << [ "#{bytes.bytesize - i} B after IEND", false ] if type == "IEND" && i < bytes.bytesize
      return out if type == "IEND"
    end
    out << [ "no IEND", false ]
  end

  def clean(src, dst, crop = nil, force: false)
    raise ArgumentError, "OUT must end in .jpg, .jpeg or .png" unless dst.match?(/\.(jpe?g|png)\z/i)
    if File.exist?(dst) # File.identical? also catches BIG.JPG ⇄ big.jpg on case-insensitive APFS and hard links
      raise ArgumentError, "OUT is IN (#{dst}) — refused even with --force" if File.exist?(src) && File.identical?(src, dst)
      raise ArgumentError, "OUT exists (#{dst}) — not overwritten; --force replaces it" unless force
    end
    unless Vips.at_least_libvips?(8, 15)
      raise "libvips #{Vips.version_string} < 8.15 has no `keep`, the strip this script relies on — refusing"
    end

    img = load(src)
    if crop
      x, y, w, h = crop
      unless x >= 0 && y >= 0 && w.positive? && h.positive? && x + w <= img.width && y + h <= img.height
        raise ArgumentError, "crop #{crop.join(',')} is outside the #{img.width}×#{img.height} frame"
      end

      img = img.crop(x, y, w, h)
    end
    img = img.icc_transform("srgb", embedded: true) if img.get_typeof("icc-profile-data").nonzero?
    # written beside OUT under a temporary name; OUT appears only after the audit passes
    tmp = File.join(File.dirname(dst), ".#{File.basename(dst, '.*')}.#{Process.pid}.tmp#{File.extname(dst)}")
    img.write_to_file(tmp, keep: :none, **(dst.match?(/png\z/i) ? {} : { Q: 95 }))
    blocks = audit(tmp)
    clean_ok = blocks.all?(&:last)
    File.rename(tmp, dst) if clean_ok
    [ clean_ok, blocks, img.width, img.height ]
  ensure
    File.delete(tmp) if tmp && File.exist?(tmp)
  end

  def parse_crop(str)
    crop = str.split(",").map { Integer(it, 10) } # base 10: «010» is ten, «08» is eight
    raise ArgumentError, "--crop takes X,Y,W,H" unless crop.size == 4

    crop
  end

  def load(src)
    Vips::Image.new_from_file(src).autorot
  rescue Vips::Error => e
    raise "cannot load #{src}: #{e.message.lines.first.to_s.strip}. A HEIC without libheif? Convert first: " \
          "sips -s format jpeg '#{src}' --out '#{src.sub(/\.\w+\z/, '')}.jpg' — then run this on the .jpg"
  end

  def show(blocks) = blocks.map { |label, ok| ok ? label : "✗#{label}" }.join(" · ")

  def selftest
    Dir.mktmpdir do |d|
      ok = ->(cond, what) { cond ? puts("  ok  #{what}") : abort("  FAIL #{what}") }
      xyz = Vips::Image.xyz(320, 240)
      rgb = Vips::Image.bandjoin([ xyz[0] * 0.75, xyz[1], (xyz[0] + xyz[1]) * 0.45 ]).cast(:uchar).copy(interpretation: :srgb)
      rgb = rgb.icc_transform("srgb", input_profile: "srgb") # attaches an ICC profile, as a phone does
      # Greenwich, not anyone's yard: a fixture carries no real coordinates.
      tagged = rgb.mutate do |m|
        { "exif-ifd3-GPSLatitude" => "51/1 28/1 40/1 (51.4778) [3 rationals]",
          "exif-ifd3-GPSLongitude" => "0/1 0/1 5/1 (0.0015) [3 rationals]",
          "exif-ifd0-Make" => "TestPhone (TestPhone) [ASCII]", "exif-ifd0-Model" => "Probe 1 (Probe 1) [ASCII]",
          "exif-ifd2-DateTimeOriginal" => "2026:01:02 07:08:09 (2026:01:02 07:08:09, ASCII, 20 components, 20 bytes)" }
          .each { |k, v| m.set_type!(GObject::GSTR_TYPE, k, v) }
        m.set_type!(Vips::BLOB_TYPE, "xmp-data", '<x:xmpmeta xmlns:x="adobe:ns:meta/"/>')
        m.set_type!(GObject::GINT_TYPE, "orientation", 6)
      end
      src = File.join(d, "probe.jpg")
      tagged.jpegsave(src, Q: 95)
      # libvips writes neither COM nor IPTC from metadata — splice both in after SOI, as a phone or an editor would.
      seg = ->(marker, body) { [ 0xFF, marker, body.bytesize + 2 ].pack("CCn") + body }
      iptc = "Photoshop 3.0\0".b + "8BIM\x04\x04\0\0".b + [ 12 ].pack("N") + "\x1C\x02\x78\x00\x08TestCity".b
      raw = File.binread(src)
      File.binwrite(src, raw.byteslice(0, 2) + seg.(0xFE, "probe comment".b) + seg.(0xED, iptc) + raw.byteslice(2..))
      before = audit(src)
      puts "  before: #{show(before)}"
      %w[APP1\ Exif APP1\ http://ns.adobe.com/xap/1.0/ APP2\ ICC_PROFILE APP13\ Photoshop\ 3.0 COM].each do |label|
        ok.call(before.any? { |l, a| l == label && !a }, "lantern — the fixture carries #{label} and the walk flags it")
      end
      shown = Vips::Image.new_from_file(src).autorot # orientation 6: 320×240 stored → 240×320 shown
      ok.call([ shown.width, shown.height ] == [ 240, 320 ], "the fixture is shown rotated (240×320)")
      ref = shown.crop(10, 20, 100, 150)

      { "jpg" => 2.0, "png" => 1.0 }.each do |ext, tol|
        dst = File.join(d, "clean.#{ext}")
        clean_ok, blocks, w, h = clean(src, dst, [ 10, 20, 100, 150 ])
        puts "  after (#{ext}): #{show(blocks)}"
        ok.call(clean_ok && blocks.all?(&:last), "#{ext}: every block on the allowlist")
        ok.call([ w, h ] == [ 100, 150 ], "#{ext}: crop taken in shown pixels (100×150)")
        out = Vips::Image.new_from_file(dst)
        ok.call(out.get_fields.grep(/exif|xmp|iptc|icc|comment|orientation/).empty?, "#{ext}: libvips sees no metadata field")
        diff = (out.cast(:float) - ref.cast(:float)).abs.avg
        ok.call(diff <= tol, "#{ext}: pixels intact (mean |Δ| #{diff.round(2)} ≤ #{tol})")
      end

      jpg = File.binread(File.join(d, "clean.jpg"))
      File.binwrite(File.join(d, "tail.jpg"), jpg + "appended".b)
      ok.call(audit(File.join(d, "tail.jpg")).any? { |l, a| l.end_with?("after EOI") && !a }, "mutation — bytes after EOI are flagged")
      begin
        clean(src, File.join(d, "x.jpg"), [ 200, 0, 100, 10 ])
        abort "  FAIL a crop outside the frame must refuse"
      rescue ArgumentError
        puts "  ok  a crop outside the frame refuses"
      end

      # the original is never overwritten: swapped arguments, and BIG.JPG → big.jpg (one file on case-insensitive APFS)
      orig = File.join(d, "orig.jpg")
      big = File.join(d, "BIG.JPG")
      [ orig, big ].each { File.binwrite(it, File.binread(src)) }
      [ [ File.join(d, "clean.jpg"), orig ], [ big, File.join(d, "big.jpg") ] ].each do |s, t|
        clean(s, t)
      rescue ArgumentError => e
        puts "  ok  refused: #{e.message.sub(d, '…')}"
      end
      ok.call(File.binread(orig) == File.binread(src) && File.binread(big) == File.binread(src), "originals intact byte for byte")
      ok.call(clean(src, File.join(d, "clean.png"), nil, force: true).first, "--force replaces an existing OUT that is not IN")
      ok.call(Dir.children(d).none? { it.include?(".tmp") }, "no temporary file left behind")

      # the walk itself, both directions: what it must pass and what it must flag
      ok.call(audit(File.join(d, "clean.jpg")).all?(&:last), "baseline — the clean JPEG passes")
      File.binwrite(File.join(d, "fill.jpg"), jpg.byteslice(0, 2) + "\xFF\xFF".b + jpg.byteslice(2..))
      ok.call(audit(File.join(d, "fill.jpg")).all?(&:last), "fill bytes before a marker are skipped, not misread")
      jfif = "JFIF\0\x01\x01\x00\x00\x01\x00\x01\x00\x00".b
      { jfif => true, jfif + "hidden".b => false }.each do |body, want|
        File.binwrite(File.join(d, "app0.jpg"), jpg.byteslice(0, 2) + seg.(0xE0, body) + jpg.byteslice(2..))
        ok.call(audit(File.join(d, "app0.jpg")).find { |l, _| l.start_with?("APP0") }.last == want,
                "APP0 JFIF of #{body.bytesize} B → #{want ? 'passes' : 'flagged'}")
      end
      png = File.binread(File.join(d, "clean.png"))
      text = [ 9 ].pack("N") + "tEXtKey\0value" + "\0\0\0\0"
      File.binwrite(File.join(d, "text.png"), png.byteslice(0, 33) + text + png.byteslice(33..))
      ok.call(audit(File.join(d, "text.png")).include?([ "tEXt", false ]), "a PNG tEXt chunk is flagged")
      [ 5, 300 ].each do |n|
        File.binwrite(File.join(d, "cut.jpg"), jpg.byteslice(0, n))
        ok.call(audit(File.join(d, "cut.jpg")).last.last == false, "a JPEG cut at #{n} B is flagged, not a crash")
      end
      ok.call(parse_crop("010,08,1,1") == [ 10, 8, 1, 1 ], "--crop is read in base 10 («010» → 10, «08» → 8)")

      heic = File.join(d, "probe.heic")
      begin
        tagged.heifsave(heic)
      rescue Vips::Error
        heic = nil
        puts "  skip HEIC — this libvips cannot write HEIC; a phone HEIC is checked by hand"
      end
      if heic
        clean_ok, blocks, = clean(heic, File.join(d, "heic.jpg"))
        ok.call(clean_ok, "HEIC in → clean JPEG out (#{show(blocks)})")
      end
    end
    puts "strip_frame selftest: OK"
  end
end

if $PROGRAM_NAME == __FILE__
  case ARGV
  in [ "--selftest" ] then StripFrame.selftest
  in [ "--check", file ]
    blocks = StripFrame.audit(file)
    puts StripFrame.show(blocks)
    exit(blocks.all?(&:last) ? 0 : 1)
  in [ src, dst, *rest ] if (rest - [ "--force" ]).then { it.empty? || (it.size == 2 && it[0] == "--crop") }
    clean_ok, blocks, w, h = begin
      crop = (rest - [ "--force" ])[1]&.then { StripFrame.parse_crop(it) }
      StripFrame.clean(src, dst, crop, force: rest.include?("--force"))
    rescue ArgumentError, RuntimeError => e
      abort "REFUSED — #{e.message}"
    end
    abort "REFUSED — the written file carried #{StripFrame.show(blocks)}; #{dst} not created" unless clean_ok
    puts "clean: #{dst} #{w}×#{h} · left: #{StripFrame.show(blocks)}"
  else abort File.read(__FILE__)[/^#   bundle.*?(?=\n#\n)/m].gsub(/^# ?/, "")
  end
end
