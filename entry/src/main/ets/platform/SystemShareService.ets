import { common, Want, wantConstant } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import {
  PreparedSharePayload,
  prepareSharePayload,
  ShareDispatchKind,
  ShareFailure,
  ShareFailureKind,
  ShareOutcome,
  SharePayload,
  ShareRuntimePolicy,
  ShareService,
  toShareFailure
} from './ShareContracts';

const SEND_DATA_ACTION: string = 'ohos.want.action.sendData';
const CONTENT_TITLE_PARAMETER: string = 'ohos.extra.param.key.contentTitle';
const SHARE_ABSTRACT_PARAMETER: string = 'ohos.extra.param.key.shareAbstract';
const SHARE_URL_PARAMETER: string = 'ohos.extra.param.key.shareUrl';
const STREAM_PARAMETER: string = 'ability.params.stream';

/** 不向业务页面泄露 Want；测试可注入 recording launcher。 */
export interface ShareAbilityLauncher {
  startShare(want: SystemShareWant): Promise<void>;
}

export interface ShareFileUriResolver {
  getUriFromPath(path: string): string;
}

export interface SystemShareWant {
  readonly action: string;
  readonly type: string;
  readonly uri: string;
  readonly flags?: number;
  readonly parameters: Record<string, Object>;
}

class AppFileUriResolver implements ShareFileUriResolver {
  getUriFromPath(path: string): string {
    try {
      return fileUri.getUriFromPath(path);
    } catch (_error) {
      throw new ShareFailure(ShareFailureKind.FILE_UNAVAILABLE);
    }
  }
}

export class SystemShareService implements ShareService {
  private readonly launcher: ShareAbilityLauncher;
  private readonly policy: ShareRuntimePolicy;
  private readonly fileUriResolver: ShareFileUriResolver;

  constructor(
    launcher: ShareAbilityLauncher,
    policy: ShareRuntimePolicy,
    fileUriResolver: ShareFileUriResolver
  ) {
    this.launcher = launcher;
    this.policy = policy;
    this.fileUriResolver = fileUriResolver;
  }

  async share(payload: SharePayload): Promise<ShareOutcome> {
    const prepared = prepareSharePayload(payload, {
      cacheDir: this.policy.cacheDir,
      nowMillis: Date.now()
    });
    try {
      await this.launcher.startShare(createSystemShareWant(prepared, this.fileUriResolver));
      return ShareOutcome.OPENED;
    } catch (error) {
      const failure = toShareFailure(error instanceof Error ? error : new Error('share launch failed'));
      if (failure.kind === ShareFailureKind.CANCELLED) {
        return ShareOutcome.CANCELLED;
      }
      throw failure;
    }
  }
}

export class AbilityContextShareLauncher implements ShareAbilityLauncher {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async startShare(want: SystemShareWant): Promise<void> {
    const nativeWant: Want = {
      action: want.action,
      type: want.type,
      uri: want.uri,
      flags: want.flags,
      parameters: want.parameters
    };
    await this.context.startAbility(nativeWant);
  }
}

export function createSystemShareService(context: common.UIAbilityContext): SystemShareService {
  const policy: ShareRuntimePolicy = {
    cacheDir: context.cacheDir,
    nowMillis: Date.now()
  };
  return new SystemShareService(new AbilityContextShareLauncher(context), policy, new AppFileUriResolver());
}

export function createSystemShareWant(
  prepared: PreparedSharePayload,
  fileUriResolver: ShareFileUriResolver
): SystemShareWant {
  if (prepared.dispatchKind === ShareDispatchKind.TEMPORARY_FILE) {
    const uri = fileUriResolver.getUriFromPath(prepared.source);
    const want: SystemShareWant = {
      action: SEND_DATA_ACTION,
      type: prepared.mimeType,
      uri: uri,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
      parameters: temporaryFileParameters(prepared, uri)
    };
    return want;
  }
  const want: SystemShareWant = {
    action: SEND_DATA_ACTION,
    type: 'text/plain',
    uri: prepared.source,
    parameters: linkParameters(prepared)
  };
  return want;
}

function temporaryFileParameters(prepared: PreparedSharePayload, uri: string): Record<string, Object> {
  const parameters: Record<string, Object> = {};
  parameters[CONTENT_TITLE_PARAMETER] = prepared.title;
  parameters[SHARE_ABSTRACT_PARAMETER] = prepared.summary;
  parameters[STREAM_PARAMETER] = [uri];
  return parameters;
}

function linkParameters(prepared: PreparedSharePayload): Record<string, Object> {
  const parameters: Record<string, Object> = {};
  parameters[CONTENT_TITLE_PARAMETER] = prepared.title;
  parameters[SHARE_ABSTRACT_PARAMETER] = prepared.summary;
  parameters[SHARE_URL_PARAMETER] = prepared.source;
  return parameters;
}
