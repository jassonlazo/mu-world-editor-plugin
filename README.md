# MU World Editor Plugin

Plugin de Godot para cargar terrenos y objetos de MU Online como nodos editables dentro del editor 3D.

Autor: `@jassonlazo`

## Funcionalidades

- Carga el terreno de un mundo MU dentro del viewport 3D del editor.
- Importa objetos desde `EncTerrain*.obj` como nodos editables.
- Permite mover, rotar, escalar y duplicar objetos con las herramientas normales de Godot.
- Exporta el layout actual a un archivo `EncTerrain*.edited.obj`.

## Estructura

El plugin se instala en:

```text
addons/mu_world_editor
```

Archivos principales:

- `plugin.gd`
- `mu_world_editor.gd`
- `mu_world_editor_dock.gd`
- `mu_object_codec.gd`

## Uso

1. Copia la carpeta `addons/mu_world_editor` dentro de tu proyecto Godot.
2. Activa el plugin desde `Project > Project Settings > Plugins`.
3. Agrega el nodo `MuWorldEditor` en una escena 3D.
4. Carga el mundo y edita objetos desde el dock del plugin.
5. Guarda el resultado en un archivo `EncTerrain*.edited.obj`.

## Notas

- El plugin no sobreescribe el archivo `EncTerrain*.obj` original por defecto.
- Si falta un archivo `.bmd`, crea un placeholder para mantener el flujo de edicion.
- Los objetos importados quedan organizados dentro del nodo `WorldObjects`.
