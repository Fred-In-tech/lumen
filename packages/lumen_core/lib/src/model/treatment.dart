enum Treatment {
  color,
  bw;

  static Treatment fromJson(Object? v) =>
      v == 'bw' ? Treatment.bw : Treatment.color;
}
