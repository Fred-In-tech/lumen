/// Rec. 709 / sRGB relative luminance from LINEAR components.
double relativeLuminance(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;
