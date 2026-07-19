import apiLevelTest from './ApiLevel.test';
import httpProbeClientTest from './HttpProbeClient.test';
import zseSignerTest from './ZseSigner.test';

export default function testsuite(): void {
  apiLevelTest();
  httpProbeClientTest();
  zseSignerTest();
}
