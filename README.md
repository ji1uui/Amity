# Amity
Amity-QSOは、アマチュア無線家が「交信する・記録する・思い出す・次の交信へつなげる」体験を一体化する、マルチプラットフォーム（Windows/macOS）対応のデジタルモード運用支援アプリケーションである。Lazarus 4.6 (Free Pascal) を用いたネイティブコンパイルにより、極めて低いシステムリソースで動作することを特徴とする。

## MVP（v0.1）
まずは最小実装として、CLIでQSOを記録しCSVへ保存する機能を用意した。実装はクラス分割（TQSO / TQSORepository / TAmityQSOApp）で構成している。

- ソース: `src/amity_qso_mvp.pas`
- MVP定義: `docs/MVP.md`

## ビルド（Free Pascal）
```bash
fpc src/amity_qso_mvp.pas
./amity_qso_mvp
```
