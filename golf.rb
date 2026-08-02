# encoding: ASCII-8BIT
#
# golf.rb -- helper for the Neovim vimgolf launcher.
#
# Reuses the installed `vimgolf` gem's Keylog parser so that keystroke
# counting and display are byte-for-byte identical to the official client,
# and talks to the real vimgolf.com API for download + entry upload.
#
# Subcommands:
#   download <id> <workdir>   fetch challenge, write work/target/meta files
#   score    <keylog>         print "<count>\t<pretty keystrokes>"
#   upload   <id> <keylog>    submit entry, print resulting status
#
require 'net/http'
require 'json'
require 'uri'
require 'fileutils'
require 'strscan' # vimgolf's keylog.rb uses StringScanner but relies on its
                  # parent file to require this; we load keylog standalone.

# Locate the installed vimgolf gem and load only its self-contained Keylog
# parser (avoids pulling in Thor/CLI). Fall back to a bundled copy if needed.
def load_keylog!
  begin
    require 'vimgolf/keylog'
    return
  rescue LoadError
  end
  spec_dir = Dir.glob(File.join(
    Gem.dir, 'gems', 'vimgolf-*', 'lib'
  )).sort.last rescue nil
  if spec_dir && File.exist?(File.join(spec_dir, 'vimgolf', 'keylog.rb'))
    $LOAD_PATH.unshift(spec_dir)
    require 'vimgolf/keylog'
  else
    abort "error: could not find the `vimgolf` gem's keylog parser. Install it: gem install vimgolf"
  end
end

HOST = ENV['GOLFHOST'] || 'https://www.vimgolf.com'

def http_get(url)
  uri = URI(url)
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request_get(uri)
  end
end

def download(id, workdir)
  res = http_get("#{HOST}/challenges/#{id}.json")
  data = JSON.parse(res.body)
  raise "unexpected response" unless data.is_a?(Hash) && data['in'] && data['out']

  # Mirror the official client's newline normalisation.
  data['in']['data']  = data['in']['data'].gsub(/\r\n/, "\n")
  data['out']['data'] = data['out']['data'].gsub(/\r\n/, "\n")

  itype = data['in']['type'].to_s.gsub(/[^\w-]/, '.')
  itype = 'txt' if itype.empty?

  FileUtils.mkdir_p(workdir)
  work   = File.join(workdir, "work.#{itype}")   # what the user edits
  target = File.join(workdir, "target.#{itype}") # the desired output
  meta   = File.join(workdir, "meta.json")

  # Note: vimgolf's `in`/`out` data has no trailing newline added here; we
  # write it verbatim so the byte-comparison against the buffer is exact.
  File.binwrite(work,   data['in']['data'])
  File.binwrite(target, data['out']['data'])
  File.write(meta, JSON.pretty_generate('id' => id, 'type' => itype))

  # Emit paths for the shell to consume.
  puts work
  puts target
  puts itype
end

def score(keylog_path)
  load_keylog!
  bytes = File.binread(keylog_path)
  log = VimGolf::Keylog.new(bytes)
  puts "#{log.score}\t#{log.to_s}"
end

def apikey
  cfg = File.join(ENV['HOME'], '.vimgolf', 'config.yaml')
  abort "no vimgolf key found at #{cfg} -- run `vimgolf setup` first." unless File.exist?(cfg)
  require 'yaml'
  key = (YAML.safe_load(File.read(cfg)) || {})['key']
  abort "vimgolf key missing from #{cfg}" if key.nil? || key.empty?
  key
end

def upload(id, keylog_path)
  uri = URI("#{HOST}/entry.json")
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request_post(
      uri,
      URI.encode_www_form(
        'challenge_id' => id,
        'apikey'       => apikey,
        'entry'        => File.binread(keylog_path)
      ),
      'Accept' => 'application/json'
    )
  end
  body = JSON.parse(res.body) rescue {}
  status = body.is_a?(Hash) ? body['status'] : nil
  puts(status || 'error')
end

cmd = ARGV.shift
case cmd
when 'download' then download(ARGV[0], ARGV[1])
when 'score'    then score(ARGV[0])
when 'upload'   then upload(ARGV[0], ARGV[1])
else
  abort "usage: golf.rb (download <id> <workdir> | score <keylog> | upload <id> <keylog>)"
end
