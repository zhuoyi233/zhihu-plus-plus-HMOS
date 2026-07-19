import apiLevelTest from './ApiLevel.test';
import httpProbeClientTest from './HttpProbeClient.test';

export default function testsuite(): void {
  apiLevelTest();
  httpProbeClientTest();
}
