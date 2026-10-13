let
  styrbar = id: alias: remote: area: color_index_helper: {
    inherit id alias;
    use_blueprint = {
      path = "ikea-styrbar.yaml";
      input = {inherit remote area color_index_helper;};
    };
  };
in [
  (styrbar "1770215585686" "Remote A1" "e212107c22737d3284e3100c2fb981f3" "living_room" "input_number.one_to_six")
  (styrbar "1770216514555" "Remote A2" "dd520d1c6bbe6e2cb502458024a7b5f1" "living_room" "input_number.one_to_six")
  (styrbar "1770217479974" "Remote B1" "47ee872251a509a205957fc30545ffb1" "kitchen" "input_number.slider_b")
  (styrbar "1770217595260" "Remote B2" "919984cb44787632a8492d1f3eccf43c" "kitchen" "input_number.slider_b")
  (styrbar "1771516552944" "Remote B3" "000afdfe339120d2eda2b784bf030fa3" "kitchen" "input_number.slider_b")
  (styrbar "1770218234756" "Remote C1" "8fa3134fa0b3121bee28782a7ba0b8f3" "bedroom" "input_number.slider_c")
  (styrbar "1770218262223" "Remote C2" "38a22b61069d668a53cee0f7a6d2e757" "bedroom" "input_number.slider_c")
  (styrbar "1772094774281" "Remote D1" "d44c7594be32a27de6bee92459f06fd9" "bathroom" "input_number.slider_d")
]
