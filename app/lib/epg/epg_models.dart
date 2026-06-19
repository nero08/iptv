/// EPG programme entry (now/next), decoded from Xtream `get_short_epg`.
class EpgProgramme {
  EpgProgramme({
    required this.title,
    required this.start,
    required this.end,
    this.description,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;

  bool isNow(DateTime at) => !at.isBefore(start) && at.isBefore(end);
}

/// Now + next pair for a channel.
class NowNext {
  NowNext({this.now, this.next});
  final EpgProgramme? now;
  final EpgProgramme? next;
}
