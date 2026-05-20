## Otimização de assets binários (futuro)

- screw.glb tem 31MB rastreado em app/assets/images/. A aplicação usa
  esse arquivo via asset_path('screw.glb') (home.html.erb:104 +
  assets.rb:13). O public/screw.glb (324KB) é uma versão anterior
  abandonada — não está sendo usado. Opções: otimizar/comprimir o
  modelo 3D e substituir o de 31MB, ou manter e limpar o histórico
  com git-filter-repo se o tamanho do slug do Heroku virar problema.
- Banners PNG (banner-tr-autofix.png 2.6MB, etc.) e cards (1.5-2.6MB)
  devem ser convertidos para WebP ou re-exportados com compressão.
- Avaliar uso de bg_segundasection.png (3.4MB) — pode virar
  gradient CSS?

Isso é tarefa de cleanup separada da migração Cloudinary.
