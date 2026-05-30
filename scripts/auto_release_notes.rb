#!/usr/bin/env ruby
# frozen_string_literal: true

# 从 git commits 自动生成双语 release notes，并写入 CHANGELOG.md 与
# fastlane/metadata/<locale>/release_notes.txt。
#
# 工作流:
#   1. 边界检测: 最近一个 git tag → CHANGELOG 最后一条非今日版本日期 → HEAD~30
#   2. 收集 conventional commits
#   3. 按 type(feat/fix/...)分类
#   4. 调用 GitHub Models API (gpt-4o-mini) 将原始 commits 概括成面向用户的双语 release notes
#   5. 更新 CHANGELOG.md 顶部,并同步 fastlane/metadata/<locale>/release_notes.txt
#
# 用法:
#   ruby scripts/auto_release_notes.rb              # 自动检测边界
#   ruby scripts/auto_release_notes.rb --since=abc1234   # 指定起点 commit
#   ruby scripts/auto_release_notes.rb --count=15        # 取最近 N 条
#   ruby scripts/auto_release_notes.rb --no-ai           # 跳过 AI,使用原始 commits
#
# 环境变量:
#   VERSION       – 覆盖版本号(默认从 project.yml 读 MARKETING_VERSION)
#   DRY_RUN       – "1" 时只打印不写文件
#   GITHUB_TOKEN  – GitHub Models API token(后备: `gh auth token`)
#   AI_MODEL      – 模型名(默认 gpt-4o-mini)

require 'date'
require 'fileutils'
require 'shellwords'
require 'net/http'
require 'uri'
require 'json'

ROOT = File.expand_path('..', __dir__)

# --- 参数解析 ---
since_ref = nil
count = nil
use_ai = true
ARGV.each do |arg|
  if arg.start_with?('--since=')
    since_ref = arg.sub('--since=', '')
  elsif arg.start_with?('--count=')
    count = arg.sub('--count=', '').to_i
  elsif arg == '--no-ai'
    use_ai = false
  end
end

# --- 边界检测 ---
def latest_tag
  tag = `git -C #{ROOT.shellescape} describe --tags --abbrev=0 2>/dev/null`.strip
  tag.empty? ? nil : tag
end

def last_commit_on_date(date_str)
  sha = `git -C #{ROOT.shellescape} log --until=#{date_str.shellescape} --format=%H -1 2>/dev/null`.strip
  sha.empty? ? nil : sha
end

def last_changelog_date
  changelog = File.join(ROOT, 'CHANGELOG.md')
  return nil unless File.exist?(changelog)
  today = Date.today.strftime('%Y-%m-%d')
  File.readlines(changelog).each do |line|
    if (m = line.match(/^## \[.+\]\s*-\s*(\d{4}-\d{2}-\d{2})/))
      next if m[1] == today
      return m[1]
    end
  end
  nil
end

if since_ref
  range = "#{since_ref}..HEAD"
elsif count
  range = nil
else
  tag = latest_tag
  if tag
    range = "#{tag}..HEAD"
  else
    date = last_changelog_date
    if date
      boundary = last_commit_on_date(date)
      if boundary
        range = "#{boundary}..HEAD"
      else
        count = 30
      end
    else
      count = 30
    end
  end
end

# --- 收集 commits ---
cmd = "git -C #{ROOT.shellescape} log --no-merges --pretty=format:'%s'"
if range
  cmd += " #{range.shellescape}"
elsif count
  cmd += " -n #{count}"
end

raw = `#{cmd}`.strip
if raw.empty?
  puts '[auto_release_notes] 没有新 commits,跳过生成。'
  exit 0
end

commits = raw.lines.map(&:strip).reject(&:empty?)

# --- 按 conventional commit type 分类 ---
CATEGORY_MAP = {
  'feat'     => { en: 'New Features',     zh: '新功能' },
  'fix'      => { en: 'Bug Fixes',        zh: '修复' },
  'refactor' => { en: 'Refactoring',      zh: '重构' },
  'perf'     => { en: 'Performance',      zh: '性能优化' },
  'docs'     => { en: 'Documentation',    zh: '文档' },
  'test'     => { en: 'Tests',            zh: '测试' },
  'ci'       => { en: 'CI/CD',            zh: '持续集成' },
  'build'    => { en: 'Build',            zh: '构建' },
  'chore'    => { en: 'Chores',           zh: '杂项' },
  'style'    => { en: 'Style',            zh: '代码风格' },
}.freeze

OTHER = { en: 'Other Changes', zh: '其他变更' }.freeze

categorized = Hash.new { |h, k| h[k] = [] }

commits.each do |msg|
  if (m = msg.match(/^(\w+)(?:\(.+?\))?[!]?:\s*(.+)/))
    type = m[1].downcase
    desc = m[2].strip
    key = CATEGORY_MAP.key?(type) ? type : 'other'
    categorized[key] << desc
  else
    categorized['other'] << msg
  end
end

order = %w[feat fix perf refactor docs test ci build chore style other]
sorted_keys = order.select { |k| categorized.key?(k) }

def build_notes(categorized, sorted_keys, lang)
  lines = []
  sorted_keys.each do |key|
    items = categorized[key]
    label = key == 'other' ? OTHER[lang] : CATEGORY_MAP[key][lang]
    lines << "#### #{label}" if sorted_keys.size > 1
    items.each { |desc| lines << "- #{desc}" }
    lines << ''
  end
  lines.join("\n").strip
end

en_raw = build_notes(categorized, sorted_keys, :en)
zh_raw = build_notes(categorized, sorted_keys, :zh)

# --- AI 概括(GitHub Models API) ---
def resolve_token
  token = ENV['GITHUB_TOKEN']
  return token if token && !token.strip.empty?
  token = `gh auth token 2>/dev/null`.strip
  token.empty? ? nil : token
end

def ai_summarize(raw_notes, language, token, model)
  api_url = URI('https://models.inference.ai.azure.com/chat/completions')

  lang_instruction = if language == :zh
    <<~PROMPT
      You are a mobile app release notes writer.
      Summarize the following raw commit notes into concise, user-facing release notes in **Simplified Chinese (zh-Hans)**.
      Requirements:
      - Write entirely in Simplified Chinese, natural and fluent
      - Use bullet points (- ), 3-8 items max
      - Focus on what users care about: new features, bug fixes, improvements
      - Merge similar items, drop internal/CI/test details
      - Each bullet should be one short sentence
      - Do NOT include category headers, version numbers, or dates
      - Output ONLY the bullet list, nothing else
    PROMPT
  else
    <<~PROMPT
      You are a mobile app release notes writer.
      Summarize the following raw commit notes into concise, user-facing release notes in **English**.
      Requirements:
      - Write entirely in English, natural and fluent
      - Use bullet points (- ), 3-8 items max
      - Focus on what users care about: new features, bug fixes, improvements
      - Merge similar items, drop internal/CI/test details
      - Each bullet should be one short sentence
      - Do NOT include category headers, version numbers, or dates
      - Output ONLY the bullet list, nothing else
    PROMPT
  end

  body = {
    model: model,
    messages: [
      { role: 'system', content: lang_instruction.strip },
      { role: 'user', content: raw_notes }
    ],
    max_tokens: 500,
    temperature: 0.3
  }

  http = Net::HTTP.new(api_url.host, api_url.port)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 30
  cert_file = ENV['SSL_CERT_FILE']
  if cert_file && File.exist?(cert_file)
    http.ca_file = cert_file
  else
    %w[
      /etc/ssl/cert.pem
      /usr/local/etc/openssl/cert.pem
      /opt/homebrew/etc/openssl/cert.pem
      /usr/local/etc/openssl@3/cert.pem
      /opt/homebrew/etc/openssl@3/cert.pem
    ].each do |path|
      if File.exist?(path)
        http.ca_file = path
        break
      end
    end
  end

  req = Net::HTTP::Post.new(api_url)
  req['Authorization'] = "Bearer #{token}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body)

  resp = http.request(req)
  unless resp.is_a?(Net::HTTPSuccess)
    warn "[AI] API returned #{resp.code}: #{resp.body[0..200]}"
    return nil
  end

  data = JSON.parse(resp.body)
  content = data.dig('choices', 0, 'message', 'content')
  content&.strip
rescue StandardError => e
  warn "[AI] Request failed: #{e.class}: #{e.message}"
  nil
end

if use_ai
  token = resolve_token
  model = ENV['AI_MODEL'] || 'gpt-4o-mini'
  if token
    puts '[AI] 调用 GitHub Models 概括中…'
    en_notes = ai_summarize(en_raw, :en, token, model)
    zh_notes = ai_summarize(zh_raw, :zh, token, model)
    if en_notes && zh_notes
      puts '[AI] 概括完成。'
    else
      warn '[AI] 部分失败,回退到原始 commits。'
      en_notes ||= en_raw
      zh_notes ||= zh_raw
    end
  else
    warn '[AI] 未找到 GitHub token(设置 GITHUB_TOKEN 或安装 gh CLI),使用原始 commits。'
    en_notes = en_raw
    zh_notes = zh_raw
  end
else
  en_notes = en_raw
  zh_notes = zh_raw
end

# --- 解析版本号 ---
# my-body 用 xcodegen,版本号在 project.yml 的 MARKETING_VERSION 字段。
version = ENV['VERSION']
if version.nil? || version.strip.empty?
  project_yml = File.join(ROOT, 'project.yml')
  if File.exist?(project_yml)
    File.readlines(project_yml).each do |line|
      if (m = line.match(/MARKETING_VERSION:\s*["']?([^"'\s]+)["']?/))
        version = m[1]
        break
      end
    end
  end
end
version = (version || 'Unreleased').strip

# --- 预览 ---
puts "=== Release Notes for #{version} ==="
puts ''
puts '--- en-US ---'
puts en_notes
puts ''
puts '--- zh-Hans ---'
puts zh_notes
puts ''

if ENV['DRY_RUN'] == '1'
  puts '(DRY_RUN=1,不写文件)'
  exit 0
end

# --- 更新 CHANGELOG.md ---
date_str = Date.today.strftime('%Y-%m-%d')
changelog_path = File.join(ROOT, 'CHANGELOG.md')

new_block = <<~BLOCK
  ## [#{version}] - #{date_str}

  ### zh-Hans
  #{zh_notes}

  ### en-US
  #{en_notes}

BLOCK

if File.exist?(changelog_path)
  content = File.read(changelog_path)
  if content.match(/^## \[#{Regexp.escape(version)}\]\s*-\s*#{date_str}/)
    # 同版本同日期 → 覆盖该段
    updated = content.sub(/^## \[#{Regexp.escape(version)}\]\s*-\s*#{date_str}.*?(?=^## \[|\z)/m, new_block)
    File.write(changelog_path, updated)
    puts "Updated existing entry in #{changelog_path}"
  else
    # 插到首个 ## 段之前
    if content =~ /^## \[/
      updated = content.sub(/^## \[/, "#{new_block}## [")
    else
      updated = content + "\n" + new_block
    end
    File.write(changelog_path, updated)
    puts "Prepended new entry to #{changelog_path}"
  end
else
  header = "# Changelog\n\n"
  File.write(changelog_path, header + new_block)
  puts "Created #{changelog_path}"
end

# --- 同步 fastlane metadata ---
gen_script = File.join(ROOT, 'scripts', 'generate_release_notes.rb')
if File.exist?(gen_script)
  system('ruby', gen_script)
  puts 'Synced fastlane metadata via generate_release_notes.rb'
else
  puts "Warning: #{gen_script} not found, skipping fastlane sync"
end
