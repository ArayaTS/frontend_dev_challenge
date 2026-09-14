import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Standard network image with a shimmer placeholder.
class TheNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const TheNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  static double? _finite(double? v) => (v == null || !v.isFinite) ? null : v;

  @override
  Widget build(BuildContext context) {
    // Deals are served at a fixed 1600x1200 regardless of how small the
    // card actually is. Without a cache size cap, every image is decoded
    // at full resolution and kept in the image cache at that size, which
    // balloons memory as more cards load. Cap the decode size to roughly
    // what will actually be displayed, in physical pixels.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final effectiveWidth = _finite(width) ?? MediaQuery.sizeOf(context).width;
    final cacheWidth = (effectiveWidth * dpr).round();
    final effectiveHeight = _finite(height);
    final cacheHeight =
        effectiveHeight == null ? null : (effectiveHeight * dpr).round();

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        placeholder: (context, _) => Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(width: width, height: height, color: Colors.white),
        ),
        errorWidget: (context, _, __) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported_outlined),
        ),
      ),
    );
  }
}
