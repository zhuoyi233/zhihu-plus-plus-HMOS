import apiLevelTest from './ApiLevel.test';
import cookieSessionTest from './CookieSession.test';
import httpProbeClientTest from './HttpProbeClient.test';
import zhihuLoginClientTest from './ZhihuLoginClient.test';
import zseSignerTest from './ZseSigner.test';

export default function testsuite(): void {
  apiLevelTest();
  cookieSessionTest();
  httpProbeClientTest();
  zhihuLoginClientTest();
  zseSignerTest();
}
