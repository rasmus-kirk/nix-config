{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.scripts;

  ff-cut = pkgs.writeShellApplication {
    name = "ff-cut";
    runtimeInputs = with pkgs; [ffmpeg];
    inheritPath = false;
    text = ''
      if [[ $# -eq 5 ]]; then
        ffmpeg -ss "$3" -to "$4" -i "$1" -c:v libx264 -crf "$5" -map_metadata -1 -map_chapters -1 "$2"
      elif [[ $# -eq 6 ]]; then
        ffmpeg -ss "$3" -to "$4" -i "$1" -c:v libx264 -crf "$5" "$2" -vf "scale=$6" -map_metadata -1 -map_chapters -1
      else
        echo "Error: Not enough arguments. Usage:"
        echo ""
        echo "ffcut <if> <of> <start-time> <end-time> <crf> (<w:h>)"
        echo ""
        echo "Where start and end time has format: xx:xx:xx.xxx. Note that low CRF is less compression"
      fi
    '';
  };

  ff-compress = pkgs.writeShellApplication {
    name = "ff-compress";
    runtimeInputs = with pkgs; [ffmpeg];
    inheritPath = false;
    text = ''
      if [[ $# -eq 3 ]]; then
        ffmpeg -i "$1" -vcodec libx264 -crf "$3" "$2"
      else
        echo "Error: Not enough arguments. Usage:"
        echo ""
        echo "ffcut <if> <of> <crf>"
        echo ""
        echo "Note that low CRF is less compression, e.g. a higher quality"
      fi
    '';
  };

  conv = pkgs.writeShellApplication {
    name = "conv";
    runtimeInputs = with pkgs; [python3 curl];
    inheritPath = false;
    text = ''
      if [ $# -eq 3 ]; then
        rate=$(curl -s "https://$3.rate.sx/1$2")
        python -c "print($rate*$1)"
      else
        echo "Error: Not enough arguments"
      fi
    '';
  };

  price = pkgs.writeShellApplication {
    name = "price";
    runtimeInputs = with pkgs; [curl coreutils];
    inheritPath = false;
    text = ''
      if [ $# -eq 0 ]; then
        curl -s rate.sx | head -n -1
      elif [ $# -eq 3 ]; then
        curl -s "$3".rate.sx/"$1"@"$2" | head -n -1
      elif [ $# -eq 2 ]; then
        curl -s rate.sx/"$1"@"$2" | head -n -1
      else
        curl -s usd.rate.sx/"$1"@30d | head -n -1
      fi
    '';
  };

  updap = pkgs.writeShellApplication {
    name = "updap";
    runtimeInputs = with pkgs; [rsync util-linux gnugrep sudo coreutils];
    inheritPath = false;
    text = ''
      set +e

      if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
      fi

      if [[ $# -ne 1 ]]; then
        echo "Error: Script takes one argument, the path to the audio directory"
        exit 0
      fi

      audioPath=$(realpath -s "$1")
      driveLabel="DAP"
      mntDrive="/dev/$(lsblk -o name,label | grep $driveLabel | grep -o "^[^ ]*" | grep -o '[a-zA-Z0-9]*')"
      mntPath=$(mktemp -d)

      isInserted=$(lsblk -o name,label | grep -c "$driveLabel")
      isMounted=$(lsblk -o name,label | grep "$driveLabel" | grep -c "/")

      if [[ $isInserted == 1 ]]; then
        if [[ $isMounted == 1 ]]; then
          sudo umount "$mntDrive" ||
          echo "Error: Couldn't unmount drive!" && exit 0
        fi

        echo "" &&
        echo "Mounting drive:" &&

        sudo mount -t vfat -L "$driveLabel" "$mntPath" -o shortname=mixed -o utf8 &&

        echo "" &&
        echo "Drive mounted. Starting sync:" &&

        sudo rsync -trv --modify-window=1 --delete --exclude="Android" --exclude="LOST.DIR" "$audioPath/" "$mntPath" &&

        echo "" &&
        echo "Rsync is finished. Unmounting..." &&

        driveUsedSize=$(du -hd0 "$mntPath" | grep -Po "^[^ \t]*") &&
        sudo umount "$mntDrive" &&

        echo "" &&
        echo "Unmounted succesfully. Disk space used:" &&

        driveSize=$(lsblk --output LABEL,SIZE | grep "$driveLabel" | grep -Po "[^ \t]*$") &&

        echo "$driveUsedSize/$driveSize" &&
        echo ""
      else
        echo "Error: No SD-card inserted!"
      fi
    '';
  };

  upkob = pkgs.writeShellApplication {
    name = "upkob";
    runtimeInputs = with pkgs; [coreutils rsync util-linux gnugrep sudo];
    inheritPath = false;
    text = ''
      set +e

      if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
      fi

      if [[ $# -ne 1 ]]; then
        echo "Error: Script takes one argument, the path to the book directory"
        exit 0
      fi

      bookPath=$(realpath -s "$1")
      driveLabel="KOBOeReader"
      mntDrive="/dev/$(lsblk -o name,label | grep $driveLabel | grep -o '^[^ ]*')"
      mntPath=$(mktemp -d)

      isInserted=$(lsblk -f | grep -c "$driveLabel")
      isMounted=$(lsblk -f | grep "$driveLabel" | grep -c "/")

      if [[ $isInserted == 1 ]]; then
        if [[ $isMounted == 1 ]]; then
          sudo umount "$mntDrive" ||
          echo "Error: Couldn't unmount drive!" && exit 0
        fi

        echo "" &&
        echo "Mounting drive..." &&

        sudo mount -L "$driveLabel" "$mntPath" &&

        echo "" &&
        echo "Mount succesfull. Starting rsync..." &&

        sudo rsync -trvl --modify-window=1 --delete --exclude='.*' --exclude='kfmon.png' --exclude='koreader.png' --exclude='icons' --exclude='Screenshots' "$bookPath/" "$mntPath" &&

        echo "" &&
        echo "Rsync is finished. Unmounting..." &&

        driveUsedSize=$(du -hd0 "$mntPath" | grep -Po "^[^ \t]*") &&
        sudo umount "$mntDrive" &&

        echo "" &&
        echo "Unmounted succesfully. Disk space used:" &&

        driveSize=$(lsblk --output LABEL,SIZE | grep "$driveLabel" | grep -Po "[^ \t]*$") &&

        echo "$driveUsedSize/$driveSize" &&
        echo "" ||
        echo "Error: Something went wrong!"
      else
        echo "Error: Kobo not detected!"
      fi
    '';
  };

  git-sign-range = pkgs.writeShellApplication {
    name = "git-sign-range";
    runtimeInputs = with pkgs; [git];
    inheritPath = false;
    text = ''
      set -euo pipefail

      base="''${1:-}"
      if [ -z "$base" ]; then
        if git rev-parse --verify --quiet '@{u}' >/dev/null; then
          base='@{u}'
        elif git rev-parse --verify --quiet main >/dev/null; then
          base='main'
        else
          echo "Error: no upstream and no 'main' branch found. Pass a base ref explicitly." >&2
          echo "Usage: git-sign-range [<base-ref>]" >&2
          exit 1
        fi
      fi

      count=$(git rev-list --count "$base..HEAD")
      if [ "$count" -eq 0 ]; then
        echo "No commits between $base and HEAD."
        exit 0
      fi

      echo "Signing unsigned commits from $base to HEAD ($count commits to inspect)..."
      echo "Each unsigned commit will prompt for a YubiKey touch."
      # shellcheck disable=SC2016
      git rebase --exec '[ "$(git log -1 --format=%G? HEAD)" != N ] || git commit --amend --no-edit -S' "$base"
    '';
  };

  screenshot = pkgs.writeShellApplication {
    name = "screenshot";
    runtimeInputs = with pkgs; [systemd coreutils];
    inheritPath = false;
    text = ''
      OUTDIR=/tmp/screenshots
      ${pkgs.coreutils}/bin/mkdir -p "$OUTDIR"
      DEST="$OUTDIR/$(${pkgs.coreutils}/bin/date +%F-%H-%M-%S).png"
      # Phase 1: slurp + grim inside a transient user unit. cosmic's keybinding
      # launcher context doesn't let slurp acquire input grabs, but systemd-run's
      # session does.
      # shellcheck disable=SC2016
      if ! systemd-run --user --collect --quiet --wait -- ${pkgs.bash}/bin/bash -c '
        set -e
        SEL=$(${pkgs.slurp}/bin/slurp)
        ${pkgs.grim}/bin/grim -g "$SEL" "'"$DEST"'"
      ' || [ ! -s "$DEST" ]; then
        ${pkgs.libnotify}/bin/notify-send "Screenshot failed" "slurp/grim error"
        ${pkgs.coreutils}/bin/rm -f "$DEST"
        exit 1
      fi
      # Phase 2: wl-copy outside systemd-run so its clipboard daemon isn't
      # reaped when the transient unit cleans up. setsid detaches it from
      # the script's session.
      ${pkgs.util-linux}/bin/setsid -f ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$DEST"
      ${pkgs.libnotify}/bin/notify-send "Screenshot" "$DEST"
    '';
  };

  weather = pkgs.writeShellApplication {
    name = "weather";
    runtimeInputs = with pkgs; [curl coreutils gnused];
    inheritPath = false;
    text = ''
      if [ -z "$1" ]; then
        curl -s "wttr.in/Aarhus?lang=ja" | head -n -3 | sed '2d'
      else
        curl -s "wttr.in/$1?lang=ja" | head -n -3 | sed '2d'
      fi
    '';
  };
in {
  options.kirk.scripts.enable = mkEnableOption "custom scripts";

  config = mkIf cfg.enable {
    home.packages = [
      ff-cut
      ff-compress
      git-sign-range
      screenshot
      upkob
      updap
      conv
      price
      weather
    ];
  };
}
