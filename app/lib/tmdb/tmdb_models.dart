/// Minimal TMDB metadata used to enrich VOD/series detail.
class TmdbMeta {
  TmdbMeta({this.posterUrl, this.overview, this.voteAverage, this.releaseDate});
  final String? posterUrl;
  final String? overview;
  final double? voteAverage;
  final String? releaseDate;

  static const _imageBase = 'https://image.tmdb.org/t/p/w500';

  factory TmdbMeta.fromJson(Map<String, dynamic> j) {
    final poster = j['poster_path'] as String?;
    return TmdbMeta(
      posterUrl: (poster != null && poster.isNotEmpty) ? '$_imageBase$poster' : null,
      overview: (j['overview'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['overview'] as String?,
      voteAverage: (j['vote_average'] as num?)?.toDouble(),
      releaseDate: (j['release_date'] ?? j['first_air_date']) as String?,
    );
  }
}
