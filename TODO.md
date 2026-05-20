## Otimização do modelo 3D do parafuso (PRIORITÁRIO)

**Estado atual:** `app/assets/images/screw.glb` tem 31MB e está em uso
via asset_path no JavaScript (screw_3d.js). Cada visitante baixa 31MB
para ver o parafuso girando na home. Em conexões móveis pode levar
20-60 segundos.

**Ações futuras (NÃO fazer agora):**
1. Comprimir o modelo com Draco compression no glTF — reduz para ~300KB
   sem perda visual perceptível
2. Verificar quantos polígonos o modelo tem hoje — pode ter sido
   exportado em qualidade muito alta sem necessidade
3. Considerar LOD (Level of Detail) — carregar versão menor primeiro
4. Remover `public/screw.glb` (324KB, órfão, sem referências no código)

Essa otimização não bloqueia a migração Cloudinary, mas é trabalho
prioritário antes do site ter qualquer usuário real.

## Otimização de assets binários (futuro)

- Banners PNG (banner-tr-autofix.png 2.6MB, etc.) e cards (1.5-2.6MB)
  devem ser convertidos para WebP ou re-exportados com compressão.
- Avaliar uso de bg_segundasection.png (3.4MB) — pode virar
  gradient CSS?
