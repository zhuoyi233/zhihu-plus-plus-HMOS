import apiLevelTest from './ApiLevel.test';
import backgroundWorkPolicyTest from './BackgroundWorkPolicy.test';
import cookieSessionTest from './CookieSession.test';
import deepLinkResolverTest from './DeepLinkResolver.test';
import httpProbeClientTest from './HttpProbeClient.test';
import qrLoginScanPolicyTest from './QrLoginScanPolicy.test';
import readerDocumentTest from './ReaderDocument.test';
import rdbSchemaTest from './RdbSchema.test';
import zhihuLoginClientTest from './ZhihuLoginClient.test';
import zseSignerTest from './ZseSigner.test';
import appStartupTest from './AppStartup.test';
import domainModelTest from './DomainModel.test';
import p1NavigationTest from './P1Navigation.test';

export default function testsuite(): void {
  apiLevelTest();
  backgroundWorkPolicyTest();
  cookieSessionTest();
  deepLinkResolverTest();
  httpProbeClientTest();
  qrLoginScanPolicyTest();
  readerDocumentTest();
  rdbSchemaTest();
  zhihuLoginClientTest();
  zseSignerTest();
  appStartupTest();
  domainModelTest();
  p1NavigationTest();
}
