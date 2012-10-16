#!/usr/bin/env ruby

require 'zlib'

logdir_volatile = "/run/mininetlog"
logdir_nv = "/var/lib/mininetlog"
flush_timeout = 60

begin
  Dir.mkdir(logdir_volatile, 0755)
rescue Errno::EEXIST
end

begin
  Dir.mkdir(logdir_nv, 0755)
rescue Errno::EEXIST
end


now = Time.now
nowstr = now.strftime("%Y/%m/%d %H:%M:%S")

stats = {}
[4, 6].each do |ipver|
  cmd = case ipver
        when 4
          'iptables'
        when 6
          'ip6tables'
        end

  `#{cmd} -t mangle -v -Z -S`.split("\n").each do |l|
    dir = nil
    iface = nil

    ctr = l.match(/-c \d+ (\d+)/)
    next if not ctr

    case l
    when /-j stats/
      iface = "all"
      m = l.match(/-A (PREROUTING|POSTROUTING)/)
      next if not m
      case m[1]
      when 'PREROUTING'
        dir = :in
      when 'POSTROUTING'
        dir = :out
      end
    when /-A stats/
      m = l.match(/-([io]) (\w+)/)
      next if not m
      iface = m[2]
      case m[1]
      when 'i'
        dir = :in
      when 'o'
        dir = :out
      end
    else
      next
    end

    stats[iface] ||= {}
    key = "#{dir}#{ipver}".to_sym
    stats[iface][key] = ctr[1].to_i
  end
end

flush_score = 0
flush_names = []

stats.each do |iface, stat|
  fname = iface + '.log'
  fname_volatile = File.join(logdir_volatile, fname)
  File.open(fname_volatile, 'a') do |f|
    f.flock(File::LOCK_EX)
    f.puts "#{nowstr},#{stat[:in4]},#{stat[:out4]},#{stat[:in6]},#{stat[:out6]}"
  end

  fname_nv = File.join(logdir_nv, fname + ".gz")
  flush_names << [fname_volatile, fname_nv]

  begin
    last_flush = File.stat(fname_nv).mtime
    if last_flush + flush_timeout < now
      flush_score += 1
    end
  rescue Errno::ENOENT
    flush_score += 1
  end
end

if flush_score == stats.length
  flush_names.each do |volatile, nv|
    new_nv = nv + ".new"
    File.open(new_nv, File::WRONLY | File::CREAT) do |new_nf|
      next if not new_nf.flock(File::LOCK_EX | File::LOCK_NB)
      new_nf.truncate(0)
      new_nf_gz = Zlib::GzipWriter.new(new_nf)

      begin
        data = Zlib::GzipReader.open(nv) {|nf| nf.read}
      rescue Errno::ENOENT
        data = ""
      end

      File.open(volatile, 'r+') do |f|
        f.flock(File::LOCK_EX)
        data += f.read
        new_nf_gz.write data
        new_nf_gz.flush
        new_nf.fsync
        f.truncate(0)
        f.fsync
        File.rename(new_nv, nv)
        new_nf_gz.close
      end
    end
  end
end
