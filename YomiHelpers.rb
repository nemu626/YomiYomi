module YomiHelpers
def refleshEntry(feed)
  begin
    fds = RSS::Parser.parse(feed.url)
  rescue RSS::InvalidRSSError
    fds = RSS::Parser.parse(feed.url,false)
  end
  fds.items.each do |entry|
    unless(Entry.where(:url => entry.link).where(:feed_id => feed.id)
      Entry.create do |e|
        e.title = entry.title
        e.url = entry.link
        e.source = fds.channel.title
        e.summary = entry.description
      end
    end
  end
end
end