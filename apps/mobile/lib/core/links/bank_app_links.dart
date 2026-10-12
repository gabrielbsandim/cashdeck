/// Links that may open the app of the bank a rail [label] names, best guess
/// first. The server sends no app link, and a bank app usually answers to
/// its own name as a scheme, so `Pix · Banco Aurora` tries `bancoaurora://`
/// and then `aurora://`.
List<Uri> bankAppLinks(String label) {
  final words = _plain(label.split('·').last)
      .split(RegExp('[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final full = words.join();
  final bare = words.where((word) => !_generic.contains(word)).join();
  return [
    for (final scheme in {full, bare})
      if (scheme.isNotEmpty) Uri(scheme: scheme, host: ''),
  ];
}

const _generic = {'banco', 'bank', 'de', 'do', 'da'};

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'é': 'e',
  'ê': 'e',
  'í': 'i',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ü': 'u',
  'ç': 'c',
};

String _plain(String text) =>
    [for (final char in text.toLowerCase().split('')) _accents[char] ?? char]
        .join();
