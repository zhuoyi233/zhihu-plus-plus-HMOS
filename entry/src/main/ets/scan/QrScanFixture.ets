import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';

// A generated QR image containing only the non-sensitive P0 test URL below.
// Keeping the fixture as base64 makes the repository diff reviewable and avoids runtime network access.
const QR_FIXTURE_BASE64: string =
  'iVBORw0KGgoAAAANSUhEUgAAAlgAAAJYAQMAAACEqAqfAAAABlBMVEX///8AAABVwtN+AAAACXBIWXMAAA7EAAAOxAGVKw4bAAADO0lEQVR4nO3dMZLqMAyAYTMUlBwhR8nRwtE4So5AScGg9xzJshQCu7NDl1/NehP5S6fxyA4p5YsxSYpnvXaWh960wdjuzm3OMpD1VCwsLCysZ7uucapW1R+rzHvPOYhcdCRy7ZfPWFhYWFhunXTCrFa9vsS1TQmWZbjlqVhYWFhY76xJrEZf+xQjhv9ortFYWFhYWL+o0aUcRbSVYD2FhZCYioWFhYX13vKwGn1TyxfB0kvzYl0026u4pmJhYWFhqZUiWmMfmDX0wbqbu72fhoWFhbU/60OMIu2QwbqKz1v5WFhYWFglnV/1jsESoUaX1myoNbrPSVX8hoWFhYX1dUszJaySa+QyP3bCBnP9E3bcajyxsLCwsBZraOag1y7l3LoPt5a57k+UbqUajYWFhYU1iRde6TV6iZCZb9TwF8TCUTEsLCwsrBpDX9D6+wopoaR2rxVr0YeIDgoWFhYWVrDseIIXa2/ASpoi4t3cuWaEp42SegpYWFhYO7YmWcellLb1FV607a0Ejbz19bKfhoWFhbVbK6x9rUZ7jOI/DOMZMT71FLCwsLB2blkFXla2deAV+Jhmz8V7CrFXm2s0FhYWFtZ3rRz+G7MWY6z3/d2HtOPWeh1YWFhYe7dqgp/uEq3Rr+e/7EZ4bCzerUZjYWFhYdWwtW9Y2Za+W2ZT1qvjoT1tuz+BhYWFhaXWSW/fumVhN/xpQ/2v3vCv0bzUaCwsLKydWpOECmyZZ80cFXBwWv79XU8BCwsLa8eWl2bPlNarXZ//GsRexbXwp7UajYWFhYU1xVbCEpPceuajnf86SIy5rY7T576wsLCwsFKNDu/XytaZLX1aRkVT65wP31nEwsLCwvqT9RqT+DraYuzT7npleFlpY2FhYWFdy/tveJXV+S8nfEFtxxNCOS9YWFhYWMX3xjRef7PruLWftlWjCxYWFhaWW7mnMK3Of0kjwmMHibFxTgELCwsLK1jSDst65rL2rTd84IQHFhYWFtb7Gm1xbnn34nHQ1NK6DmF1jIWFhYW11VOYWsIo+fzXpS15L8XfwP2hP4GFhYW1RyvFM61svbmQvzXjcS3+Hti7/TQsLCwsrL9bX4x/j6kr9/XiptcAAAAASUVORK5CYII=';

export const QR_FIXTURE_VALUE: string =
  'https://www.zhihu.com/account/scan/login/p0-api20-test-token';

export function writeQrScanFixture(cacheDir: string): string {
  const path = `${cacheDir}/p0-zhihu-login-qr.png`;
  try {
    const bytes = new util.Base64Helper().decodeSync(QR_FIXTURE_BASE64);
    const file = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer);
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (_error) {
        // The caller reports fixture preparation failure; closing must not hide the original error.
      }
    }
    return path;
  } catch (_error) {
    throw new Error('无法准备内置二维码测试码图');
  }
}
