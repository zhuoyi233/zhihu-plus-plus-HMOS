import apiLevelTest from './ApiLevel.test';
import cookieSessionTest from './CookieSession.test';
import deepLinkResolverTest from './DeepLinkResolver.test';
import httpProbeClientTest from './HttpProbeClient.test';
import qrLoginScanPolicyTest from './QrLoginScanPolicy.test';
import readerDocumentTest from './ReaderDocument.test';
import rdbSchemaTest from './RdbSchema.test';
import zhihuLoginClientTest from './ZhihuLoginClient.test';
import zseSignerTest from './ZseSigner.test';

export default function testsuite(): void {
  apiLevelTest();
  cookieSessionTest();
  deepLinkResolverTest();
  httpProbeClientTest();
  qrLoginScanPolicyTest();
  readerDocumentTest();
  rdbSchemaTest();
  zhihuLoginClientTest();
  zseSignerTest();
}
