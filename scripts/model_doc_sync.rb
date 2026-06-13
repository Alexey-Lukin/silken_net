#!/usr/bin/env ruby
# frozen_string_literal: true

# Doc↔code sync gate for docs/04_01_Data_Models_and_Entities.md.
#
# Replaces the manual "§12 SSOT Drift Register" invariants (which were prose and
# silently went stale — the doc claimed 35 models while app/models/ had 36) with
# an automated check. Enforces three invariants:
#
#   1. Model files ⟷ `### `Model`` headings in §2..§7b (1:1).
#   2. Concern files (app/models/concerns/) ⟷ `### `Concern`` headings in §1.
#   3. PartitionMaintenanceWorker::PARTITIONED_TABLES ⟷ table names mentioned
#      in the doc (§0 + §11).
#
# Pure Ruby (no Rails / no bundle). Run: ruby scripts/model_doc_sync.rb
# Exit 0 = in sync; exit 1 = drift (lists the divergence). Method/why → docs/00_06.

ROOT       = File.expand_path("..", __dir__)
DOC        = File.join(ROOT, "docs/04_01_Data_Models_and_Entities.md")
MODELS_DIR = File.join(ROOT, "app/models")
WORKER     = File.join(ROOT, "app/workers/partition_maintenance_worker.rb")

# Files under app/models/ that are NOT domain models (skip in the 1:1 check).
NON_MODEL_BASENAMES = %w[application_record.rb codex.rb].freeze

def camelize(snake)
  snake.split("_").map(&:capitalize).join
end

# file path under app/models/ → expected Ruby class name (Codex:: for the subdir).
def class_name_for(rel_path)
  parts = rel_path.sub(/\.rb\z/, "").split("/")
  parts.map { |seg| camelize(seg) }.join("::")
end

def doc_lines
  @doc_lines ||= File.readlines(DOC, chomp: true)
end

# index of the first h2 line whose text contains `needle`
def h2_index(needle)
  doc_lines.index { |l| l.start_with?("## ") && l.include?(needle) } or
    abort("model_doc_sync: cannot locate h2 section containing #{needle.inspect} in 04_01")
end

# `### `Name`` headings between two line indices (Name = first code-span token).
def headings_between(from_idx, to_idx)
  doc_lines[from_idx...to_idx].filter_map do |l|
    next unless l.start_with?("### ")
    m = l.match(/\A### `([A-Za-z0-9:]+)`/)
    m && m[1]
  end.to_set
end

errors = []

# ── 1. Models ⟷ §2..§7b headings ───────────────────────────────────────────
model_files = Dir.glob(File.join(MODELS_DIR, "**/*.rb")).sort.reject do |path|
  rel = path.delete_prefix(MODELS_DIR + "/")
  rel.start_with?("concerns/") || NON_MODEL_BASENAMES.include?(rel)
end
model_classes = model_files.map { |p| class_name_for(p.delete_prefix(MODELS_DIR + "/")) }.to_set

models_from   = h2_index("2. Біологічний")
models_to     = h2_index("8. Seeds")
doc_models    = headings_between(models_from, models_to)

(model_classes - doc_models).sort.each do |m|
  errors << "model in code but NOT documented in 04_01 §2..§7b: `#{m}`"
end
(doc_models - model_classes).sort.each do |m|
  errors << "model documented in 04_01 but NO app/models file: `#{m}`"
end

# ── 2. Concerns ⟷ §1 headings ──────────────────────────────────────────────
concern_files   = Dir.glob(File.join(MODELS_DIR, "concerns/*.rb")).sort
concern_classes = concern_files.map { |p| camelize(File.basename(p, ".rb")) }.to_set
concerns_from   = h2_index("1. Concerns")
doc_concerns    = headings_between(concerns_from, models_from)

(concern_classes - doc_concerns).sort.each do |c|
  errors << "concern in code but NOT documented in 04_01 §1: `#{c}`"
end
(doc_concerns - concern_classes).sort.each do |c|
  errors << "concern documented in 04_01 §1 but NO concerns/ file: `#{c}`"
end

# ── 3. PARTITIONED_TABLES ⟷ doc mentions ───────────────────────────────────
worker_src = File.read(WORKER)
part_tables =
  if (m = worker_src.match(/PARTITIONED_TABLES\s*=\s*%w\[([^\]]*)\]/m))
    m[1].split
  else
    abort("model_doc_sync: cannot parse PARTITIONED_TABLES from #{WORKER}")
  end
doc_text = doc_lines.join("\n")
part_tables.each do |table|
  errors << "PARTITIONED_TABLES `#{table}` not mentioned in 04_01" unless doc_text.include?(table)
end

# ── report ─────────────────────────────────────────────────────────────────
if errors.empty?
  puts "model_doc_sync ✓ — 04_01 in sync with app/models/ " \
       "(#{model_classes.size} models, #{concern_classes.size} concerns, #{part_tables.size} partitioned tables)"
  exit 0
else
  warn "model_doc_sync ✗ — 04_01 ↔ code drift:"
  errors.each { |e| warn "  · #{e}" }
  exit 1
end
