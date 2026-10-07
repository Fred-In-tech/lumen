import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/features/cull/library_filter.dart';

/// The top-level sections of the app (left rail on desktop and tablet).
enum ShellSection { home, projects, allPhotos, looks }

/// Where the app shell is. The editor opens on top as its own route.
sealed class ShellLocation {
  const ShellLocation();

  /// The rail item lit for this location.
  ShellSection get section;
}

final class HomeLocation extends ShellLocation {
  const HomeLocation();
  @override
  ShellSection get section => ShellSection.home;
}

final class ProjectsLocation extends ShellLocation {
  const ProjectsLocation();
  @override
  ShellSection get section => ShellSection.projects;
}

final class AllPhotosLocation extends ShellLocation {
  const AllPhotosLocation();
  @override
  ShellSection get section => ShellSection.allPhotos;
}

final class LooksLocation extends ShellLocation {
  const LooksLocation();
  @override
  ShellSection get section => ShellSection.looks;
}

/// One project's page; a null [projectId] is the Unsorted photos.
final class ProjectLocation extends ShellLocation {
  const ProjectLocation(this.projectId);
  final String? projectId;
  @override
  ShellSection get section => ShellSection.projects;

  @override
  bool operator ==(Object other) =>
      other is ProjectLocation && other.projectId == projectId;

  @override
  int get hashCode => Object.hash(ProjectLocation, projectId);
}

class ShellLocationNotifier extends Notifier<ShellLocation> {
  @override
  ShellLocation build() => const HomeLocation();

  /// Goes to [to]. Leaving a photo grid drops its selection and filter, so
  /// the next grid starts clean.
  void go(ShellLocation to) {
    if (to == state) return;
    ref.read(selectionProvider.notifier).clear();
    ref.read(libraryFilterProvider.notifier).set(LibraryFilter.all);
    state = to;
  }

  /// One level up: a project goes back to Projects, a section to Home.
  /// Returns false at Home (nothing to go back to).
  bool back() {
    switch (state) {
      case HomeLocation():
        return false;
      case ProjectLocation():
        go(const ProjectsLocation());
      case ProjectsLocation() || AllPhotosLocation() || LooksLocation():
        go(const HomeLocation());
    }
    return true;
  }
}

final shellLocationProvider =
    NotifierProvider<ShellLocationNotifier, ShellLocation>(
      ShellLocationNotifier.new,
    );
