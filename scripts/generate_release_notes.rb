#!/usr/bin/env ruby
# frozen_string_literal: true

# 从 CHANGELOG.md 提取最新版本段,写入 fastlane/metadata/<locale>/release_notes.txt
# 仅写入 fastlane/metadata/ 下已存在的 locale 子目录(避免误创建未使用的语言)。

require 'fileutils'

ROOT = File.expand_path('..', __dir__)
changelog = File.join(ROOT, 'CHANGELOG.md')
unless File.exist?(changelog)
  warn "CHANGELOG.md not found at #{changelog}, skipping"
  exit 0
end

content = File.read(changelog)
lines = content.lines

# 取第一个 ## 段(最新版本)
start_idx = lines.find_index { |l| l.strip.start_with?('## ') }
if start_idx.nil?
  warn 'No version heading (##) found in CHANGELOG.md, skipping'
  exit 0
end

end_range = (start_idx + 1)..(lines.length - 1)
end_idx = end_range.find { |i| lines[i].strip.start_with?('## ') } || lines.length
section = lines[start_idx...end_idx].join

# 按 ### zh-Hans / ### en-US 拆分
zh_block = nil
en_block = nil
if section.include?('### zh-Hans') || section.include?('### 中文')
  zh_idx = section.index(/###\s*(zh\-Hans|中文)/)
  rest = section[zh_idx..]
  zh_end = rest.index('### en-US') || rest.index('### English') || rest.length
  zh_block = rest[0...zh_end]
end
if section.include?('### en-US') || section.include?('### English')
  en_idx = section.index(/###\s*(en\-US|English)/)
  rest = section[en_idx..]
  en_end = rest.index('### zh-Hans') || rest.index('### 中文') || rest.length
  en_block = rest[0...en_end]
end

# Fallback: 没有子段则整段都用
section_body = section.lines.drop(1).join.strip
strip_heading = lambda do |block|
  block.lines.reject { |l| l.strip.start_with?('###') }.join.strip
end
zh_out = strip_heading.call(zh_block || section_body)
en_out = strip_heading.call(en_block || section_body)

meta_root = File.join(ROOT, 'fastlane', 'metadata')
{
  'zh-Hans' => zh_out,
  'en-US'   => en_out
}.each do |loc, text|
  dir = File.join(meta_root, loc)
  unless Dir.exist?(dir)
    puts "Skip #{loc}: #{dir} 不存在(只写已配置的 locale)"
    next
  end
  next if text.empty?
  path = File.join(dir, 'release_notes.txt')
  File.write(path, text)
  puts "Wrote #{path} (#{text.bytesize} bytes)"
end
