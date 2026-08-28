# amnezia-vpn для NixOS

Nix flake, собирающий **AmneziaVPN 5.0.1.5** для NixOS из официального
`.run`-инсталлятора (формат Qt Installer Framework).

Инсталлятор *не запускается* — derivation вырезает из него встроенные 7z-архивы
и раскладывает содержимое по nix-store, после чего `autoPatchelfHook` перевязывает
все ELF-файлы на библиотеки из nixpkgs.

---

## Что внутри

| Выход | Описание |
|---|---|
| `packages.x86_64-linux.amnezia-vpn` | сам пакет |
| `nixosModules.default` | модуль `programs.amnezia-vpn` |
| `overlays.default` | оверлей, добавляющий `pkgs.amnezia-vpn` |
| `devShells.default` | окружение с `p7zip`, `patchelf`, `binwalk` |

Состав пакета:

```
$out/bin/AmneziaVPN              # обёртка (makeWrapper)
$out/bin/AmneziaVPN-service      # обёртка для привилегированного демона
$out/share/amnezia-vpn/{bin,lib,plugins,qml,translations}
$out/share/applications/AmneziaVPN.desktop
$out/share/icons/hicolor/512x512/apps/AmneziaVPN.png
$out/lib/systemd/system/AmneziaVPN.service
```

---

## Установка

### Быстрый запуск без установки

```bash
nix run github:terrentii/amnezia_vpn_nix#amnezia-vpn
```

### Как flake input

`flake.nix` вашей конфигурации:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    amnezia-vpn = {
      url = "github:terrentii/amnezia_vpn_nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, amnezia-vpn, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        amnezia-vpn.nixosModules.default
        {
          programs.amnezia-vpn.enable = true;
        }
      ];
    };
  };
}
```

Затем:

```bash
sudo nixos-rebuild switch --flake .#mymachine
```

### Только пакет, без модуля

```nix
environment.systemPackages = [
  amnezia-vpn.packages.${pkgs.system}.amnezia-vpn
];
```

либо через оверлей:

```nix
nixpkgs.overlays = [ amnezia-vpn.overlays.default ];
environment.systemPackages = [ pkgs.amnezia-vpn ];
```

---

## Опции модуля

```nix
programs.amnezia-vpn = {
  enable = true;

  # какой пакет использовать (по умолчанию — из этого flake)
  package = amnezia-vpn.packages.x86_64-linux.amnezia-vpn;

  # симлинки /usr/bin/{wg,awg}-quick, см. ниже. По умолчанию true.
  linkWireguardTools = true;
};
```

> **Важно.** В nixpkgs уже есть свой модуль `programs.amnezia-vpn` (для пакета,
> собираемого из исходников). Два модуля объявляют одни и те же опции, поэтому
> этот модуль содержит `disabledModules = [ "programs/amnezia-vpn.nix" ]` и
> *замещает* апстримный. Если вам нужна сборка из nixpkgs, укажите
> `programs.amnezia-vpn.package = pkgs.amnezia-vpn;`.

`enable = true` делает следующее:

* добавляет пакет в `environment.systemPackages` и `services.dbus.packages`;
* включает `services.resolved` (клиент правит DNS через `update-resolv-conf.sh`);
* регистрирует юнит `AmneziaVPN.service` из пакета и включает его в
  `multi-user.target`;
* кладёт в `PATH` юнита `gawk`, `iproute2`, `iptables`, `procps`, `sudo`,
  `wireguard-tools`, `amneziawg-tools`.

### Про `linkWireguardTools`

Готовый бинарник ищет `wg-quick` через `Utils::usrExecutable()`, который смотрит
**только** в `/usr/sbin` и `/usr/bin` — записи в `PATH` недостаточно. Поэтому
модуль создаёт через `systemd.tmpfiles` симлинки:

```
/usr/bin/wg-quick  -> ${wireguard-tools}/bin/wg-quick
/usr/bin/awg-quick -> ${amneziawg-tools}/bin/awg-quick
```

Если вы не хотите трогать `/usr/bin`, поставьте `linkWireguardTools = false;` —
протоколы OpenVPN, Xray/VLESS, ShadowSocks и Cloak продолжат работать,
а WireGuard/AmneziaWG — нет.

---

## nixConfig / бинарный кэш

Flake не тянет собственный кэш: всё, кроме самого `.run`-файла (96 МБ,
скачивается через `fetchurl`), берётся из `cache.nixos.org`. Секция `nixConfig`
в `flake.nix` лишь фиксирует стандартный substituter:

```nix
nixConfig = {
  extra-substituters = [ "https://cache.nixos.org" ];
  extra-trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
};
```

Если добавите свой кэш (Cachix и т. п.), допишите его туда же; при первом
использовании flake Nix спросит подтверждение на применение `nixConfig`.

Если вы собираете не от доверенного пользователя, Nix напишет
`warning: ignoring untrusted flake configuration setting 'extra-substituters'`.
Это ожидаемо и на сборку не влияет — `cache.nixos.org` и так подключён по
умолчанию. Чтобы Nix принимал настройку, добавьте себя в `trusted-users`:

```nix
nix.settings.trusted-users = [ "root" "@wheel" ];
```

---

## Как устроена распаковка

`.run` от Qt Installer Framework — это ELF-лаунчер, к которому в хвост
приклеена цепочка 7z-архивов. AUR-пакет `amneziavpn-bin` находит их через
`binwalk -qe -y=7zip`; здесь то же самое сделано без binwalk:

1. `pkgs/find-7z-offsets.py` сканирует файл на сигнатуру `37 7A BC AF 27 1C`
   и печатает смещения (в 5.0.1.5 их семь, шесть из которых — настоящие архивы);
2. каждый кандидат вырезается через `tail -c +$((off+1))` и распаковывается
   `7z x`; ложные срабатывания просто не открываются и пропускаются;
3. распаковка считается успешной, только если появились все шесть ожидаемых
   объектов (`bin lib plugins qml translations` + `.desktop/.service/.png`),
   иначе сборка падает — это ловит смену формата в будущих релизах.

### Почему здесь нет `wrapQtAppsHook`

Инсталлятор везёт с собой **полный Qt 6.10.1** в `lib/` и `bin/qt.conf`
с `Prefix = ..`, благодаря которому Qt сам находит `plugins/` и `qml/`.
`wrapQtAppsHook` из nixpkgs выставил бы `QT_PLUGIN_PATH` и `QML2_IMPORT_PATH`
на **другую** сборку Qt, и в вендоренный рантайм подгрузились бы
ABI-несовместимые плагины. Поэтому стоит `dontWrapQtApps = true`, а бинарники
обёрнуты вручную через `makeWrapper`; связывание с системными библиотеками
делает `autoPatchelfHook`.

Обёртки лежат в `$out/bin` и запускают настоящие бинарники *на месте*, в
`$out/share/amnezia-vpn/bin` — клиент и демон ищут `openvpn`, `geoip.dat`,
`geosite.dat` и `update-resolv-conf.sh` относительно
`QCoreApplication::applicationDirPath()`, то есть через `/proc/self/exe`.

---

## Обновление версии

```bash
./update.sh
```

Скрипт берёт последний стабильный релиз с GitHub, считает sha256 через
`nix-prefetch-url` и правит `version`/`hash` в `pkgs/amnezia-vpn.nix`.

---

## Сборка и проверка

```bash
nix build .#amnezia-vpn -L
```

```bash
nix run .#amnezia-vpn
```

Проверить, что не осталось неразрешённых библиотек:

```bash
ldd result/share/amnezia-vpn/bin/AmneziaVPN | grep 'not found'
```

Проверить flake целиком:

```bash
nix flake check
```

Проверить, что модуль собирается в составе полноценной системы
(`module-test.nix` — одноразовая тестовая конфигурация):

```bash
nix eval --impure --raw --expr '(import ./module-test.nix { flakePath = builtins.toString ./.; }).config.system.build.toplevel.drvPath'
```

---

## Ограничения

* Пакет бинарный (`sourceProvenance = binaryNativeCode`), только `x86_64-linux`.
* Платформенный плагин Qt в поставке один — `libqxcb.so`. Под Wayland
  приложение работает через XWayland.
* Для WireGuard/AmneziaWG нужны симлинки в `/usr/bin` (см. `linkWireguardTools`).
* В nixpkgs есть пакет `amnezia-vpn`, собираемый из исходников — если вам не
  нужна именно свежая версия из официального инсталлятора, используйте его.
