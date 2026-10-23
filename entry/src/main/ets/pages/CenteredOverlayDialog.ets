/** Native dialog placement stays centered on phones, unlike SheetType.CENTER. */
@CustomDialog
export struct CenteredOverlayDialog {
  controller?: CustomDialogController;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  private emptyContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
  }
}
