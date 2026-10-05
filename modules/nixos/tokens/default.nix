{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.tokens;
  source = ../../../age/shared/tokens;
  tokenFile = name: source + "/${name}.age";
  perUser = f: concatLists (mapAttrsToList (user: names: map (f user) names) cfg);
in {
  options.kirk.tokens = mkOption {
    type = with types; attrsOf (listOf str);
    default = {};
    example = literalExpression ''{user = ["GH_TOKEN" "LINEAR_API_KEY"];}'';
    description = "Env var tokens per user. Each name needs `age/shared/tokens/<NAME>.age` and is decrypted to `/run/tokens/<user>/<NAME>`, readable only by that user.";
  };

  config = {
    assertions =
      mapAttrsToList (user: _: {
        assertion = config.users.users ? ${user};
        message = "kirk.tokens.${user}: no such user";
      })
      cfg
      ++ perUser (user: name: {
        assertion = pathExists (tokenFile name);
        message = "kirk.tokens.${user}: ${toString (tokenFile name)} does not exist";
      });

    age.secrets = listToAttrs (perUser (user: name:
      nameValuePair "token-${user}-${name}" {
        file = tokenFile name;
        path = "/run/tokens/${user}/${name}";
        symlink = false;
        owner = user;
        group = "root";
        mode = "0400";
      }));
  };
}
