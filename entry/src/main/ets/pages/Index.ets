import { P1Destination } from 'core';
import { BackgroundTaskProbePage } from './BackgroundTaskProbe';
import { DatabaseProbePage } from './DatabaseProbe';
import { DeepLinkProbePage } from './DeepLinkProbe';
import { DomainFixtureProbe } from './DomainFixtureProbe';
import { P1Shell } from './P1Shell';
import { QrScanProbePage } from './QrScanProbe';
import { ReaderProbe } from './ReaderProbe';
import { ImageProbe } from './ImageProbe';
import { TechnicalLabPage } from './TechnicalLabPage';
import { HomeFeedPage } from './HomeFeedPage';

@Entry
@Component
struct Index {
  build() {
    Stack() {
      P1Shell({
        homeContent: this.homeContent,
        technicalLabContent: this.technicalLabContent,
        readerProbeContent: this.readerProbeContent,
        imageProbeContent: this.imageProbeContent,
        databaseProbeContent: this.databaseProbeContent,
        deepLinkProbeContent: this.deepLinkProbeContent,
        qrScanProbeContent: this.qrScanProbeContent,
        backgroundTaskProbeContent: this.backgroundTaskProbeContent,
        domainFixtureProbeContent: this.domainFixtureProbeContent
      });
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  homeContent(navigate: (destination: P1Destination) => void) {
    HomeFeedPage({ navigate: navigate });
  }

  @Builder
  technicalLabContent(navigate: (destination: P1Destination) => void) {
    TechnicalLabPage({ navigate: navigate });
  }

  @Builder
  readerProbeContent(onBack: () => void) {
    ReaderProbe({ onBack: onBack });
  }

  @Builder
  imageProbeContent(onBack: () => void) {
    ImageProbe({ onBack: onBack });
  }

  @Builder
  databaseProbeContent(onBack: () => void) {
    DatabaseProbePage({ onBack: onBack });
  }

  @Builder
  deepLinkProbeContent(onBack: () => void) {
    DeepLinkProbePage({ onBack: onBack });
  }

  @Builder
  qrScanProbeContent(onBack: () => void) {
    QrScanProbePage({ onBack: onBack });
  }

  @Builder
  backgroundTaskProbeContent(onBack: () => void) {
    BackgroundTaskProbePage({ onBack: onBack });
  }

  @Builder
  domainFixtureProbeContent(onBack: () => void) {
    DomainFixtureProbe({ onBack: onBack });
  }

}
