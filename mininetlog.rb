#!/usr/bin/env ruby

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


stats = {}

now = Time.now
nowstr = now.strftime("%Y/%m/%d %H:%M:%S")

`iptables -t mangle -v -S`.split("\n").each do |l|
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
  stats[iface][dir] = ctr[1].to_i
end

flush_score = 0
flush_names = []

stats.each do |iface, stat|
  fname = iface + '.log'
  fname_volatile = File.join(logdir_volatile, fname)
  File.open(fname_volatile, 'a') do |f|
    f.puts "#{nowstr},#{stat[:in]},#{stat[:out]}"
  end

  fname_nv = File.join(logdir_nv, fname)
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
    File.open(nv, 'a') do |nf|
      File.open(volatile, 'r+') do |f|
        data = f.read
        nf.write data
        nf.fsync
        f.truncate(0)
        f.fsync
      end
    end
  end
end
