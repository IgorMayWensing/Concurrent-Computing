#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
cc -std=c11 tools/wrap-function.c -o tools/wrap-function \
  || echo "Compilation of wrap-function.c failed. If you are on a Mac, brace for impact"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      �<�v۶����@�!eɖ�Įܺ���Ա��rӳ�.-A7ɐ����������>B_lg�A����u�k�����`0�c���׾��R���&>�ۛ�)�7�����퍭F���߀,��籔�Y;!!�8z�F�p���ES������Oт/���͍��������	꣙7�]߻��.����f���66��!���~~���O��]��څ�+���=>�گ��;��f��ѻ�n�Y�!�J\�,}�K�~�wD��!u��4H��c�A�(}B�#��R�`���O�WHZ������7|bH�7&M�2r��E��)��8114B�%�Ť�6YJp�%l�h�{~�ID�;A��je�u��s�;�W�R�q�%�&������ll>���HO]o0�)�6����:ޫ�Y��]f��B��%������$���4�1e�;��a�� f���NX k�"~Rgh�4U���� ��`�j!�q�*�,fhs�)�bA�:tcZ\����aHS��L�ᄗ��Bx��ȯ�ʙXH��ɺ�� S��4�G�%�!�"��d��5F�ч�$VH�Y�&Ϲ��:���M<� �ȟ��>y|\#U9Hqb#�J��O3U|����6��B�DЯI�O�4�����F�D�/��β�(#P+e�kk$a����Y7A����z��m�ղ��B��z�]�(���P�!�/؀��Yg2�f���7����Ȋ|g���[I����@�XGM+�b��i l� �l&-��,���cj8�"����W��m�_��V����r��i��"+���/��B���<Tg���9�CZJ��罘���S�e�����K�گ�̢�^���XY����y��_�U��KƓb��@�e#�L�j5'bf�aF0��V��e�~&�YV:�/��'�	u�YP�YLi2���}b�s�	�P���@���>H��g�1�h�-�tP"r=�a���]��}�n�ymœa��
C�MpzU��is��̹MYa�ґ�̡0���}������j�2����g��4�ڝ���*�_�lRQj��RS�\Q��<����D�ڄ<kB�̠	*;|5R��{!z����Z��C�TxO� V Z��pT"	��#��w�M��4��s�_�1K����ye��H�d��M��뼶;?w;'����������*���CO�S R~�k��67����lHSn:��JSsgs���P�/w^�=p����3�����T�L�W�ݸ9P%#�"#?`��Fh�N�(�h�槞u:?� EQ�̃Sf�2#��N&�Kq�:]�5�V�hXd}9�D�ػxy5���I�k�-KC�V��V�tRs��sA�?�i#�`9|��_��Z �kCi%�m�Hh�:��l2d�CHIj�X,���/��A�����'#� ��Q��ǸgbM-�f�G��,+]����!'>:�C���I5�րi�7(��tA��%;R�%�}�� b&��Rۋf�ٛ:�`��&P��+�9]݉��$�(8�♻|�Ӂ���&��5Q"��deEe_ՙ�5��ğa?�ܐ����0�����C!�Q���-�Ap�|�T�뚘&���]Xf��@�O�G5d*���{�-��p�o�fI�:y�x���K�]i)�#Z5����lf��Dn�vg(bN;�P���Y<��"UY	k�8,����|���:���YNB��̆h#vV&�~��Iy�UM�ve�®�;J����p���+{�.KxKĘ
M!���'<k�|��i-;�� E_Tһva�J�Oy�`�/��j"��u���4��Vퟒ�����3��kǍ﯎��V��ws�����I=�{{t��~����~{�U98}�m/���������F�U�s����O���
��{�X����7����՚7�L*�����F�R6xDW�����3[�N�!��K&xu��M�� �PE�@
m7�㑟DHN��� ��ٞ8�����1�O"�<�9R���v w��}]dwoH��#���҈~"K�3�h4�4 K�����WP��t�����G~ ��_	����ry�����\�	��)e�:���㕈̦$�guu�r���/=�Ͱ���Dbwb\���?!lP��.Ȝ���*������t�`>�;H���]����J���T���(�<����7��xW!���Ԥ�Y�D`7�#2�+�##G���t�|H/����~�VF.!�����T��R���_����QǢ�};;�om�?��<HR����w����}�E���[�
��a3Ng(=�$�Q��6�#\h��`�5�0�*�r2#J����<J
7`��@\��/58�6.�dE6�6�f��ms�6�C��~N΋K�0}�>�wa怿Jr�I�:�5c\������KXe�zgs�����?}�t��c@Z8�����4I}��c���jZ��������� ��CVE�\Y2M	�Ҵ,YI������;��=���-�kQ��3���b[nI �\:��k���p�gt����}e����]���D����Іp�ͧ5�!�[T+��2��g��+ ;x��4AQ>z�%װd �Z��
� do/�\&Ɇ^W� _��@:�H)��˼%�NI�d���U�5T�:����6I�x����a5݂��$`,}CӣZ� �6�2�.�C��č�YL�#�3ؙ%wiY��>�)� U+b�y��V�����A�4CQy�;DJ�����Y�7���"���Lܡ�a=�[�K��?��v.�{���� �;�tDl�o��G����wv�s���sr���mW��X:B�u�|�h6��X�(;�J4ώ/lk0��D���n�ʇ����8�?���r��荦q���V��&^s��.��c/j����]s⃏��L#:�
IzYPO��A̶F��t�(��kvl��c�f^�^z0���JQ��̐AF9"s�%$� }��?�]�Qa%����|ԅy:�{v����
�w�w��m�Yc�b�X����P��;�H�U��`c�{�)c��CQ���ֈ�ָ��&�*��9�`B%+�/��N�
�@����]x!�Z}�̳ٞk�Ye�-����T՚�h~*dV'�h�E��HX�6
����dC�E8(n��u1~D-���yg�e1���ǵj�ɩ�=:p�����r�ck}#���	������iډ`X�_w'�����Nՙ�y3�l=o�����h���kz��#ܧI���)<����k�]���;@�Z�B<
\o�>"m��b^�9��V�]�	�h!�N���%�`����������̐ 쳷G'�����`�Pߟ����Y)�S��T�1�L��Dʞ�"�Ǝ�AeN_�0XLX�<t2_֮�R��4f�<*��T�\0+U��E��������8;��d�jĜܓ��F^ |�K{�ϼx�r�����k�0�rº��B�4�cN����g�7H�_"BwLΡ�M���M��ܒ<���q5���J���X3�	uV¬P�&Ċ��2�ᰦ1�>x'�=y	T%�'���y�ܹ�s�H�Rr�w��C�27��j��gn�Iy$�X�b��kE=PS4#��aA4 K]�$Y�ؚ��|�eK?!�"���n7�"�-�}C<Gv�F%ri��nдȡ9|GdG��m��2Yъ6'�N�4-�������_���3�t����xq#����+f�!a,m%Y�>�b�?d(VR[K�ZDjB��C�iIja!���\�ԛ}��i{���B��e��E��jk$Y!}��)._i��^���d\ZQ�c�VVʴ�M^�+]t55+}�c.`>�*�=!o�����\���Χ����}<���d�=cD�JX��q4Q���P�� L%�)��H�[�B�$[z��D�/4ᲊ~�4A�3a#}���30�\2&��gu ��Pt��,+}�ԘBt�6�`[L��/����E�g:YJ�Kϑ.Y�܂K�D�}j�n�9.٠Uf��X���d�	c��8��,��Z��F��|N}9��{Z"�����\x	<�8ҳ4g_��8�Y�� �S���c������i����F�	嶄t��"Y��o�C�@y��}�x�������Q (X�a2V�+���������*`�`@��=x\
��S�q�jm�|e�'Eu(�|z:�^���ն�&*p]�-1|Ex+��\��uiw���{�b/ZpT�ueU��*�=��������ִ�<�u�O�7��{Q?d�X����'�?��.6|8z���C�w@��Y�*~�����}��� �}n�t�z0�����1^�bru=�q�n'�E��p΢� ��L��<����u�qG�E!U<��?�/W�' X�%���{�����2��a���������O��+���Y|��h~�#2q���芘��rt�����Ԭ4K$(����&���	~�_�F�;�1�&��c�����e�h�6��uݽF��UN�,>����>�������5�j����g��j���js�6W_�d�V�E�l�n����f�����m|476���F �W_�7��b��������W�^l��4���K��l��!�v�����\��&Jx����?�Ub�N	�����|UA������\���\]���r��<x|��Wۀ��i<����Z�d�KS��L<bW���胃�A��mjv��6q�ƚYoJ#������U1�U��4ҋ�8�Y7�=eO@�����y�1U�� +	�5�W�4��c�?pp�UG����nǷ��� 8o�SIn@� ��`[�3 ��� t�(P0��2�|Q��ՙ���w��h�,\>�%~T�[ W喯=�YM��]ٝ[�ǉ�U17ؿ��,ܛR	��Oz�0���F}p���/�㣆��$�~֮6%��6�������@"�sf�\6��V��jţ6���T�
������	�E�]�����=�������~�X�������#�=��?D*��K�����4�J�q��=Svt�K(��3��lvώ�Aw�5��\�"=��stwBj��� ��:�- K�AŬ�G���`�mg��4���Ĺ�C��`�N)z���S�z��tMl�FO��N{q-#�]0��;qH�y�d����h���XW؟]
���-ǚG���a��9�(����ݑ�H��7���3z���� �(����*$��LTL�� 
V��᮴���X���_����S'bK���	3�"3���[$yL��̓��_E�К��3JShw3$d�"��7\�Į7�����I�`��J�S�
��Ž g�mj�Y:@r�?t��z�`��MX�`6�B_����#_��?�5�x?u,����\�'��>����C�A��Dnө�_V����~�9u��,v\'"�����+O��w�9�O�8�r��v��C��l��d����?�~"&{�}p���']���Sc�~ތ��#���@����]��ߖ�z��$p�|�+(�d��������l0#��E��g-�]O��s�??�?p�� ��7�M�����Ǉ V���3��d�@�Z��_7n/�V��w��a�R��ٷ���#�r���>��j"�=�}rz���Z�[�v�׮W����N��G�/���Ϋ��m�?��?��휴~zA췧gG?�����w�v��x�xy�G\�v���b������i��������ۭͬ�on7��C�������:������Eۓ'jhfƤ�wȳ��!���������a���t��^�^�Q❭U��9ȩ0TC���oM��8���yeK��`�m�Ƞq@dV��� �a��C��k�Y�⸑���b���� ��]X���b��d7q�43t<����~L>��=g?��_��U��Z�<!�/}vc�[*�J�RU�T�w&������t�-���Et�.�Q��"P.����itv��$ך��:�Q'8��	q�2�[_�.�;P���ˎo&��l:-b�ۜq �<|�������m~����p1ǵP�"��`�K����"Q�C�����<E�Pv'�!�\uOW�;���Z�L~L0:�s�6D���TSЀj��(N�!���HKj�f����Lp�9J:��3� ճ�F:�"*c�ksu��'!f�8���R%k� ��~�ɳY�y��|N���O�<N�x�������<�ojŪ+V��^�x��(`vN���48�~ �
W�죂����7��/�[lKxOt��U��k9�W�J��-)`%|%��6u�t�;�X��[\�by"_JA*>�yc��3I2cQ)�!Ps����d��'#<�楢qd�o'FW�z ���$y�x:\���T������q?A.Y��c�
b�Y]�\D��ꕃ��̠��9ʞ ��-N&P��M|]\�d�7��$�$b���Q�u�8��>��ș\_�:����f�������Y*�\C��@��#�����F�s8Q�w�ZV4/>���4x:����`B�*���ӏ��w荓�z�����綑�+UOVHF��Pn++M�]'�I;�L
�!�uz}���G�v�:���O���ݽ/7�p���g`�
H�#QmO���os����WK�b	<:���=W��MA���{�M(��we��������H(_�-M���QKl�l1���Ҽ\���o����y[M(��,A����G}��텒>Y����*���)&S�D>�8"��ƌ�"��0q���VfF��_2�_~&�����Ŵ�A,M��|�~]Q�d3x��XF+��Y�g)�$�t�\���%��k���S�:=gEf������"�HGէa�6���A֜�{�GQ�46E�2���Zw���I��J�y g&�F>� ��皚E���f�l�uf�,��H����Њ��9�f�������˪9�f�Q�U�/��e�IR�
��h�g(������lW�J<���fO�%c��x�85�R��0Ħ�cQ�~shɆ0����U�Zf�	a�,�ϧ����d�1Y�O3w *�@)�������y �v�-�*%�
�*Ƭ}U8��<��<�ZJ�5���"�:���2h+�q!��VnW���2R�)�8Wf_M��&�.Q?�ս�"X{Q��:>�:�0����Z+j��=Q��U��M���%A�j�ea\Y,��Gc���'=���<d��[�s��6��Q>����-��iʖ\kz�2S����,H�;%�����A��;�k�{*�vg^}���ٞi��ZͷY�X���5�
� d�n��Vh�(��Ոނ�oD��`�nck�Y��o_�+��<Z�E�g��釷|�|t@���rw��SC��<��ͧb����څ������t�������%@Q�!����`�@�:�<�p8D;��q8b$k�]�.�O����F��Ȏ�O?�kp)e���IaG|�Y���p�n�ԕ7�ߺ��I#�yu����h����.�є]�5��J�� �S~H.�8� �Vu!���C��.!�q��6��� �r��\Fπt��")H�iqH�\uUӠ�O՞nr>��悚�մ�9�l�Є�b��2���ľo��B,ʁ�@��%��L�	��k�y:R.�r����?WYx|-���v�i)�H3ǧء9��M!��t�~��-��r
�t��e�I�MM�r+���ڇ	�w@rw͘�+�a��M0��k�8;n�������櫃Ý�n�9Jay���D`tO`#�Q{��h8�Q8��t��x�L�x7������.���*�D�Pm���Y����}��1#�DWP7�O��ֈ��0�Vɘ
<AM|��F�8���+\����
�����z��x����v{O�Х؃�zԻJ&�^����i���b���S�w�*�<_�S	3L�#��R1$*�cx�e�� |m� TU����p������r�YP��\��:�Ȑ�N�,T)v9jo���܊�.�k�š�ق��cV6w�̊ 2ŕ�"�P�j�ddc�*�
�h'�('5*u ��7uSZ�d��ǻ�q�E����T�ܯ��I8�4a|�%�}N�A�Äc����"�E%��p:΁�<�e�mJu$��hR3m� �Y	� �J����YDP�J�L�c/���S�]"���AfAe;揔�-�ضsf�A^5�0I\�pGVW����Z��~2���t��U~4�d�7ҙV'D
��u���4Ʉ�Y�����?����Ƣw�h������`�3� oﰹ��!S��O�!f6r67�dO��a�|�Ա#8N,�����E]���p 񩂶!��*Ê��i�� gl�IEe�1���[X*3�:���*��"2RA_��u�^���ט(_���lW_[|KB�i^giS�ʯ��{	�2�)'�;�5;�g�W�c�OU�aE{r3uP�����,+�J�r"���Zf��������E�{��U<��P���y�g?�l���íPW:���1*���+h_R�)�^č�����P�%���-��GЯ��5��tV8o���X�^�cA�Gϓ���2�?�#�"q�+,�TVKX]�-�yPҚͿOJ���T�=��t�y�;%�2}g�Nӂ�z�<�c\��ۛz,��-v��ZCZ�aj��:|{����W���\���`/<m[�n��<�ۇ��>�'a!$�s/�'`fq�ö́�:<�6{産����LN4�xԶ�6��m&�#���Rpr�X%�+�J�^�(���ۘ�7�e���'ϗt�Ӫ�t��諓N��R�K���tylg��$�� �g a�8ff��u"$@�
���Џ_�o=D��-�{���^���%"}ME_K���m>�b��&0Z�b+�Z��]��ig+`�cd��f.�,��̚WOv/���F�B��&e��K�	�ls�����$�T��*�{��Y����VgX%�.ػ�vO\O,��{�����g��|ηN�]ƾp$n�ZAC��L�,����"��z������j�ծq]K��k�~+�{1N��-��V���K�s��0��k�\gs� _)�O��ǿeN��̠�-��s�	𜨲�~�m;qPi��$��q���x�eQ�uw�4L4[�Y��(Զv>�Y��%��,LR%��Oo����Sb`��gJ�{�X����(�s�R+s��DLa�j�"ŀ������DfDqb��7	����=L��l8:sr8�2��K'qpĸ���@�>.T�#R\Kb~GFY&X�{2>8k�ʦR��6]S��T��>�,/�G�l�~O6bk��+Q�f�G��y��Ӝ��:�Z��y��TxR�$͘�K@�ٳ� �)-���"��R���8A�+�[�t3����)q��p�n�{��(�;73��n
����r�;�F�L�Q�T�qFCPa@q��a h�fP�����t����u�yo4��YE��Q�Tq���&�-"K�����Z��SL� �@3��h,� ��Dl63$M��LM]��(N�W�䑘-~�,�$N�t���BP�G\Ae��Hc`+27ae������a��ūMm�/�������I6��7�;Q��Bis����h���N����/�#~��h��G��"��;���o��SOǔ_�������I��`w�2hp��=cΒ��%'����c��͂�CU3�G��t(P<D��LC������ڟ���3��k����Rai�p
��ag<�w�w%��v1��f�+�)ə�L��ES	j�ŧe8,��sc5��Z�.��u�}��b{k�Ցn�g���tqΐ�,.ɭ����lf&��\�|B�h��VnL���p�����y0���L,����$ >t���pZ�AΒp�	,(��,'�p�� �}�d�κ�����gm9��A��]S��x3<WDZ�����%�Z3�7�J���'���D`�1�N
���9���u �`��XC�c����Xf���$���e�߫*��-g$'�ιg4�%��8bW�='��>NN��(x�=\N��?N�(F���.��۰VCY;���9�&1c��`���~��=�M�w� D��d�������r�N�����m�Q�b��~�z��<��q<:��\� "E�p�p13�I�f����P=MiȺ����ӑ8rW"N�Cj���Y;"�d���q���U�r��扦�ٗŴ��(^��*s�Aq!���X��4�`���9����qn�~|�b�X�؜�k�r�{(�ׂۜ���o�c�-r���x���^u�L�a|;�,{��c�F������/s��N5�gX��ꆥiT��+��Y1���=x@Yf�$�zL��\U>_��*�JeW7�\�v�����Oߡ6�6����;����=������x����F�y���}�U¾���\�u�?��3��sO
�A��9%��$U[�4�q�<Ee�}2�r&��ٚ����� ]dQ�*��0������/՝��	 :���Q"�p���=������LJ��N���:6���kyw��X��e��&�eˈ�D���O�����\�{RY�]��Qz���\YR�E�E�8����X�q�O�4+��`�G��%�Q�j2��Xs�vi����<���|n .X�a��Z�?����Z��+yq�O�|�n2�Ȍ��(�*NV��1FIm->��db��8:=�8�B�!}�&^�^%��Yz1�_�88y�T?��=h>54��E�t�$L�|Tɘ�o�m�����[:y��s�OA���3�Y�|��E�-�3���h

��ģ?��ͿX@���F�MXĳ[D��AJ�z�m��b�Do��^��e��ښ\��f�t0���%�SW�`��%� ��k�"|2�{�!|�S+t�4@0�
��/�Ӻ��� 5�����X�莅
5{i�)\�����9����7��|.�X\a�l�ɚ[X::�1��x��+����h����%�.�r][C�2��^�8S�;=M�ԃ|$~�cXg?vf���+�if/����\�8š.Z�͟ӿ��^���:�Z�d2�6
�?|���ғ�7��u<z�1�n�`�m����?Z�n���?���y~��g���q2'�`�//�����?[�����hc_�9 �0:ǥ�_S�]���U�)~�bq4���AqqVչj�"�3\���7�N��73=�,:� �t�ښBz��
���cg���m�� x
�wLN�,*bD��V�D��PN|�ħ�O`N�稵�F��~H0�iV9�V��lIi������!���,�j��(v<=a�$&1�K�6�n��	B��ci>�ۇ`@��it�v$aӔ�;e�r�.!��oW^7ɄQT�)�)��cSɂ�𵾟.]2E�߂��E��P(�h%d_��E�HRq���ňk&��M�)_�J�6��=���Xhؚ�6e�mFT��=�9�E3:��'`�3�']���뒬V��>gg��.p��-�{rT�nv����%�^�aǇ5��>�RU&�BhrRm$�����N�� 1�ӡ`!�ϭf���cc�ػ8Y�����l�H)�;&�m}�x��(��Ksه���WD�� c�B#��O��b�6Ƽ��7�J0h^�3��ɫ��(+ڐ�������7�󀹃*
�?�_1��XS���j�9[��镜�U%�|z��[9o�+�t��"
lCQ�[p�P3Ņ�*���߸�5v~���؞�d�m��m����T�0��Q��^^ʾN�:-#P.�_�R�& I�C.&��C�ca��w�=���TP�Q	���M�6�Jƒ�������;cɁB�iQ��wv���9zR*�(�9-WU�gVm�}0��n8�h�jCZMQlI��5��h�T�ט���Zz�`Շ0g��`��Ez'j��β���?-J�?nhTDY��u��g�C�cP�''j�����=��`�I{��z�%%$`B| !srb
��Y���G�$b/���T�cK�|�O��6A�%��@X5�F��ƨ�C�ߎ�7a��"U���k���KHj؄�B���ćuI���?�"���h$u��b}�Ä��[�B�U|��S��Q������}bJ��0�Px�&�b��iX�l4=)�<��Z�T�v�*��,��I�br����%DJ�M)��~�k0NF��衔=e���	�|�4ޮ2c��&�v�sK3�\0�����p�<c��f0�*�B�o�@.8�Rs�J����k�AKI��B����'m��<4�j%��Z�Q����B����w/�S����KP�WA�'LydP/��U-h8VU�P3?�#-��~��t5�V�ՉG���'��[�|����b��Ǐ����WR��Wn��幽�>��mP�*�Ev�FM)��U��؝/�Ol��˄bYpd��5���W���^��:Z��B����{�y{8���n�6������%�jv	Jr�M?�C�-�J��DI��G�3��fOp�_l-�V��5��8�" �O��kR���o{���+�",���@)[����e�C��6���)L}�W�b7�l�V]cx-UN"ޏ膦"_�n�����u?���=?�x���{���R���ӊv�ޫ��l��Y���k�v����
{���K!3���DĎ��o�é���xU��������<p�a���g>���>ZN��<������-84�K��e��q�����ݳ����g��UJ��U��o��n��6��n��'φ���Tʮ �L��J�M�߳� l��׏#�͍k鄝��#�==��fJ���x�/XA�AP�k��Mh?E�&OӤ/���nͨ����f+.�}h"�L�*��"l���I؝� Y(v;��->�|���g`U�lp��рv��\"5�贇��`T�����[�4;�K�zW)ц1�����[s>>@`e��aY�R��M���9]Z<�T����7�L>��{�ˀ�L�8U���߫��S��&}��i�̼xZ��k��۹
W�^�
\����1rN���������C&�d�)���E���2���eg}4��mþ�4S�,���+i�sR�W�nT�Na�6��f��1)tj�`|�K��̈Y����܉��w�l����tz��~b��H9iGOpש�[�$�VU������~�)���j�bf���%�	)퟾��U���u������z����:dH�����[>���ޒ��Q���Y����h�����g������u ɚ[���Ýo:��ýW���+KK����]�<eͽ%��iU��a�V�S�;�7���ko��ˣz���%�y����}��ԅ�|5�Wu��
�M���xTloaew�K���������ۇ���N��כ�t�%a|�8�a���A�� ��4:%���fmB)�>�[��v��q6a���H�g��`�p��2@�/d�F�Ph��$@�/y��6���/���S(z�ۂF ����MBa��r��c	�u���HPv�xp������K.�~�����!���P�*rr�ס��d2^m��,�ͤ� �5'�q����w�r�f "�)(7�k���0���6ɾ�G��m�x��ه�?c�Ө�k�Yl���u�a8#�ÚC3XD�0�?�`s.<\�S{��A�c��n����������:�+@OA�h��Ʃc#���D����Y��I;�&�Ӂ�]��;p���:;	ޓ'�'qC����J�p�oLۢ��6�F�1 ;�(��
f�]����I2=N&�.`�۸�����::��ư��؃��� G�M�^��|xĔ�u4��*wj�Y�����5��N�rk��{*=���JK�|7��	 ^�$�_u�7��B�9�;���:knC������7��h ��	4�p��H���I�!�i?1n��~����﫯���}�u����C�%�����Ў(��¶���fG��_l�w��z�y����Pw�L�<(W���W�+�VSD��$�~>��_m`9��>nA��s��.�yt�q���^o��]��4r0Î�7���:{.�!�L���{���V�� ~+��\}��PAns�m��7xI��FN��q�q@�R���r!�����P|Z�'a���W��e�Κgj"�A!����2Gp��KY%푭�t6�_�M�w��X�n��,�CAX����H�J�9��HJݩ�p��v@������w�(IhNl=c�)� ��a�c�M
�q��R9
h!�Ԩ G���[L�z�����˿�b3f+�g���"�$��6蟏d�U�3�~�o����6"��/r�w� �	A#7�HȌ�Ӏ�uq/1�3�F%�(���[E)��b!Q��M���h��#�*-��)	ZZ��2NU��pц_r�n�:��3!o6��<t�Ο�R8�� ���G��$�UA}���)�x���J���7"��Q��u���R������ �F�F<�MNv����a��Q���{��I��̜�����o{�w`ֽ�իek�gUL�����>�x������F����eX|WŬR���1|&�*�r`�y������)w�%���n��2l߲�*�n�!ʯ� ��^�E6`.rm#��N�O�[M�u�k��ͯ)��Io���̔��
���I��� ��rkp�=6t;�7ec��� o�|����$��:�8q�ġ��L�&���I4%"%u�q��At�+9C9+3Tg�G�4�%���8�4%�]��΀��G?:�2����*�o�BьϙS����R�D/�ыm]A�u���sV6�+�E����v-�tZο�B`�A�ݱ�D bdҢ�5$��Fөb�f��[_�tr��~���G�K���y���:�;T��Q�S�E�{�A��'1�I�wU<��H��d͗�V���wUqxc�fiS(�8��ox$UZ�w��8`�ѐ4äB8�1 �Bo�h��Ҝ�P�S�`5�<Z�\x��`�.�D]޴X�*��X0����0(����j�y�a��68�&AX�լ���5T�C����@����|E�M�m3{׍[�ۛ;{�W���*�l9���z�5���|�I��*TC��������vu�~Bކ�Q�*�8�'HA�#�TH�.5U^�𢆌q���F ����?��yn����yn������ @ 