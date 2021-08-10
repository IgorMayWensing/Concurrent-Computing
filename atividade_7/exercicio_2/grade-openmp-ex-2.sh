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
�      �=�V�H�����(���_ $00�$�g�d3����ePbKI�O����>¼�VU_�-K6I�tr��]]U]U]]�]RR/IO���r�]M������Z_k�wy�iu�֚�f{m��f��Y_��־K�5IR7f�;���I9ܼ���+U�O�p�|+�|�w�:����+���؍�I�O�0��������VN�WW;wX�z�Ͼ�����ʩ����y��˝{�G�O�{ݭ�V�ݗ�G[��0���y����lV��-kx��&�m����N��e�![б0�y��Y?!j,S6'��%A��)k����7�
5pǜ3���2YU�-^�i���Z��qB�0���7J<z�"hV�*U��
��k��_�_�0�K�����ɏ��f�v���u�����c�%���Ϸ+zQ�g����?5�b��{�E?HY����ƔMNZc�$��>�()럻q�����sA[���@��ܾ�-����8�9�~���p��WL�l�z�5�~`�7>�+����>I/gc%���:���J���*qϼv?a�� '�U'D��P��b/��k��
�xq̶X��#������m���۫���8r�}�l��B�=���$8�U%VH�	�u&���7N��^TլYg����RY��(!����
S�q���i�aA�<���I�q�k9�f!p�ONڛ�0��v(�d��6��&�j��¾ݪ�鍼�&��lI>�^[��Rkɵ�#h-�"hU3�-�#``��[�����g��h�L��i��Z��ß����~f;�%S�2�)KѭCem�@�*-�kF䦔�	Gx�DiMD(�ߎOR֫��n��N�����N�W�Ee''5�k���}rb���W��������p�)�N��DL�f��km\����Z͆�Y���?��`+��&�-�/׉ӛ�T$h�~rRU ƴ�mu���wQ��z����]���N��.��!{��@Dٖ���Ɛ�b8���紵Y��\f�Ph���|
(l������2�[����|Ve߱fY�s�HT�l:B��P��B)q�y8i@���D�ڄ<�B������=��B��\ӷ^��j��(�*�@����D�%��;�����60�����Y��<$�6v����4~_g/�Ϝ�G���ݧ��~����~L^�?D��� ���9<<lja*g ������@K-#��B&��O��r�ۃ��ǟ?S�,ZW�1�I��9wE!���56D/2#�G��bK*1��0�8�����)�:d�bpKg�9bH�шpi����A/�^\�}9R%GԮ ^\D�r��t:RE����Jf�a5I+�Y��9����:!�ᕥ~�Bj��/,��X=���2`�IVd=	'��!&ib��Y����M��B�w��!��Q��GܓX3�e���p4I�5�礇ȡA��#�!���.܄��Bo�5Nw(g�_� �|�V�hr���9��I��KhlǞ$�S���n�?G�
��J�5g�;Q�����.����׷�#5م�.(�#"C�dKK:��ͬ���8`�{��ď�;���q�Q�{ d��q�mIsQ��Y�n�9"y)�6a���Ο��ZL&����A�Z�����5D��A����bwiKH�������*_��&�K��,� E�q�T��,�a�K]y	�8(����|��$�|9�Qh�"��}De劮Wuw�UW��ۥ�*�.��(�����(�j/S��Ę	MC@��n�-a6ڦഞ[��f Z,*�]�0�J#0�<�0k/)��q�����޿z���\�����x��O��Ɯ�v{������ĥ����}��~O�{G;[�ʓ�W�G[���;����Z���}��Γ_��*h>�0kA�Z�?�Yx�V��hT���$u^����Cʁ����������A�[6D��E�`�5܁D��x
}7>㑟l�N��D���ٞ8���rٖ�'�Y�)T���~ w���|Y$��wDa���|~@�x��R�<MF��R9<"��������)�<��P��J ��t���E�$��7b�?�hB�ȋ�`��J�&c��~���l	�L�J����X�˴�ؕ��q��2��2�X�Ս]k�?��t�`~�vC�C���`�q)�	%TpOPyk�^�֟-5oj����4�j!Xǝ�	@����5����x�|X/�u~?�+C��
4�;'����x��o���̋��Ƽ������>�����ȥ���g/w�v��WG��#|nW*��C3�������$�X���5(�fƽ�CG_�f�y�S��v&��RW@.N���K�C��÷��(�m.\�FaL;��츸���{n����3/m�Z3����!~�>��w� >8�Ukt�aγ~��{��-�6,�B'�>0��k6���sm��* ��K`��_n}@w�)�H]��K�-a�Zժ$2���o���<���d�]�JLXM����T�L<��k��x��l����Le�����V3����,#��p���5n[T{��3o wr�o�
�n�<K�̄�k���2N�V�!�ޞ�.	F�aҪ1h�W�<��)�rq��d�I�I��qV�^ yR���6ىu�=<��(]B�K����xF� Wb���n~���$� !8��̒��D�a"f�ŝ д@�����r���r��j�m�QTn�qe�����.�߫뫷��7qe������qC�-�_�����v{}*�{�u��y#�=�!s�����>�9:x�u�~��?����q*�(���af���t�h>��(_�����9驃i�y�(���Yy�z� ��s���J9O���� `+lA�='����LÍi���ҟq���B�A4�������Hy}�U�����}�ؿI��gLn��&ad�Ѓ �)$3�CKP(� {p�~t�`F��|������ӹ���g��]�v�q����½N�b�X�����{�4u��.��Q��`�=�c��CQ����e��}�T��$�8y���W��Y������}x)��x8�gG��k��j��y��Mժ�:�O��Z�ƉVC]$D�A����Rz�ࢸQ9�i?�J?�#w^�٦"�//@�R+u9��� �z��������:����\���o�9M�	����	��8ȿN��e����f��M�s-?$+�d�R�0b�0�1M�<���|��!߾64�}DlTiȓ�Fa�-�F(�5���`�}�8"�a!����]�`0�ƞ���˒P]&L�P@�����m������j�j_4�Z��;,m}��r���s�=�b*��rư�盧�`�R�W&�	+�������Y*�$��%��
�f�J�!���D���<�p����.�N&:IaSϘ�{����+D�y���I�nV.�8J�g��V���)%ψ�����a�!����c�tCl���7��rK�<u�.���l�B,
�M9��bM*�TC^H�	���LE�6�5���Bt"�ѝ�P� 4�~"��jΝ�b�YYZ�TF�ձl0�,̲���N��	n�Iy��x��õ"�5��DFY4�D�4��$I�bk����-��̋�:
ns�D [`���yX�T��E�,O�thF���gM�!��hi�V��������$���!K��a	?��J1�f���/V�XT�������!�}*��?d*���6���P��T8�ZJ)�������H��E�HdM�ZF6�pO�B��"	1�c�Nq�R��7�z�G %�Ҋ�=ZZ*��-�B�wP3��c�1��s�m���]�=�w~�����?	,�<���d�=OcD�JXڞ�hfCӆ��C��  ��L��sj#�o9u���>��N���%�^�4�x���>�[��/��I��Ym-}5��A�-DW�
�����r�J��T�N�R�\�x�tFy�rN��<���]s\�A'H��(�����`l@P��5�
��c��S� ���D��%r+����E���W�7�������6g2#i����:g^�0�������>�3`B{[B�F3U��o{�9������,�]^�	fN� P���6,��P	ۆ�#il�'U��?�4�-�ip��NoSө5��QL�-��d���Yc����Ӂ:l��+j��l�uc���6.P��E�
���i �Rű�_��\b��Eޛ��"B��/�ԋ�!;F�ZD�^������Z�b��ݟp���= �D窱&~�������ѫClZ��4���`~�	\D��0�t�/J�\� �`� ��M'	�?���)��j&��4��S%����=�T��cgo�\���`�O��Q��sh>[�_*�q�!��b��}��4�@x(��/���rD�@��C{�3YL.��l|k5/�	�a-�9���ru�?���q�|�r!Nq�&��B�e��xY'�j�p���v���j'v��Ͼ���G��`��z�ܩ�v{����h�ݪ����:<�-?zL�v�Q��.�?Z��Z�����u��VW���f :ˏ;M�=Zk�m��:�g�ᣇt[�A��?��Z��� �v����oN�VWD��_r�'�J��b3 w���W���
{�����,ۤ�ݐk����u _m~��c�'�B�
���=\yB�$F�m�� ��9ɷ��E�߱���f�%��N��;m�آW��G�b9fR�S�Cs��0^���ѝ,) 1j��8h��cۯ8����ۯ8�����zq�{��#?��(�^���g ��~���L�K��A�E� �g��7���E�g�іp�V�n�R�[���n���v�w2�+Q�bnҿLeUܛ�	��Of���_��7��fO�~��5\C�I�]�J�x�\V�_n�Z(��3+��ӷ$�@�h(!�����#�PZMv��ڗ6�������Xˣ����ל������������M\���s��h�Nc�����o���̅Z�u���WQ�:X�&ה�5���k����������������XWK�޳3����F��O���d�8���V�!f�<��Q2rcg,>��Or��� ���rO��Z�{C��j�v�-�(�/���c?M=R{�,>S;��ZV:�M��]Ec2Ԟ��(v��.1�����J���/쳀\���`o L�A�7�2f|��D���_��{c�9�%����H�0�=�O�#r���l��\F���i�*�o9޷���muZ E���H��/��q���
��2.�3W����Q^en���;L�]q�%zY� ���{���`���,m��>�os��
�C_��B~�N���5��5Z��ԡ��j�J�Z�z���c��Dڹ����C�p�d� i�F���q0' �
���#Ʌ���!(-EKo�k1�&_Q����n�AYc5�>?�[�Hu���z�')?��>�,�~��H����������;��:�d,�T�G	����L���0 ��\��T�/<�����@�O��/ZOf�yw�p�k�i�)3v�&��=�ɬ8��.{:G�{anQ��R)S�H��E�� �}{̭n��u�}�C~O��`����?�Pz���q��e������`��4F?��w x��������{�Hy���(LXm8���Ko �y�h�2�r���`hG� @�1h�˂~��r��"������6�]t�O�P7��8���:蜟s0u|T��c���4�D�r�D� �L(|۴�HB������F_�vܻ���d��X?0�kM�>,�L$�Q 5�P5N��MiB|����1�3l����9�(���wM�����s������I�����s���_�<��K����\��0�A�=<�}OG�A�w�2�(���C`6C����{��}��N��-�a
��wG������mnI�_1� 1XJ�=�BbB��8'WǮk"Ml�e�8�Tݏ��T݇+�������=�7�y��-���
bif�{zz�E3j����t�^s�M��
��[@1��0�,"B˷�6�|�os���G\� C����p-�����8)i"�AX}������4u�	��ݾo`Ba�	��p�>����*q�QE������q��;�74�n�����Ͽ���>(���)&K�0GW��=kk�bi�4��q�؍9�W���c3i�y�&Z@��a�2��s�n8	84����e���ó�1k�g0���ŖV&[�-2+���k�A�4����&���Jճ�U���i�)=I2
�$W�Y˧��Js���%�X��*R�D��/e���a�Q�$E���X��M�h�O7�O���_�e�weC�4�^$�E���Q���9i�4�M�i��>s�?��p�;��6����B�_OHV�����\�s�hܴs ��{kM����Q�(�������l�vGf�V׊N���*��"����,Y����_�\Bw���0V�3��^��L���Fd��d�^��3��t����0U$�����O���?�!�oӡN�CD���cϟ|��iʮ=0�9�b���p	�]$)����9�:\>Gf�ճm����z��u��2��_9����(�����7�N��m.��}�R���g���Zv�d�^0I��IP��>�J�Ax��wJw�_�ӓ�ӓ��-��3�R_��5�M��*
u��u��Ũ/�!�3��i�S?�1L~���ܑ8 Z~3�s_8��e��wC'@�Ė�Q��=��)�,�m�_���US�LZ>�l�|,�	�0��0R�X]~,L��,u�C���Ʒ�D�9c��r�2��m�?'���؍` �"'i�DZ\������[���]���N��>������)�/��v;M���	{��=�����G�Ç��n�;{����N��x�Մ������Q3�xa�{_�H�=a�ׅ��`E�{�������|#q��f-i�䛡c,�VTSz^D_�(�J���}����*�VU�X�{�Q9�z�i�؃�ڤ�ӊIEx)�3���X�59R���)�#)���?��p\x6�zG@������H�pLާ
0��8}����$�O(T���>Q�?T� ��'����c�e�}��:A��R4=Wp�������L:�&�}�1����5���	�'���H-�h���EzcV̗1!����Pr�2�PC�~��kkD�Hώ�% g�����k�ˡ�<[�Ih��_�"X!Ӱ�)92�wpBv�>8��G��B�4�+��OO�+�
4c���"D�q��V%�����\Y�  WFԿ[�^��vZ�S��X�#MTDɏW�t�>��r�a�Rs�ߤ-��sk�c7���h4Ź���OO'K���z��V�~�8���mo�I�Ӝru�"�c���%��I��ŉ��5�;N��XA:<��e1��*ʸ�i���Nt �B0Be���}��U�tq�U����qM���R�C�����'{�C�K���tg�k��C�i�� �&��Er����]n�r�ځ�#2�d� �� I2p �v��`���|CE�8�Rw��F �m�hI��$;�����V����Z���y�$��eZ��Z��%�Yi =��2�$?�̪��7
�K��褻��U5��yC-����1�Ke�U���G�
AޑY*�h�gݾ�Ѳ:�5�Rr�~5�ۼ\�+~ͨ�ۅ���a,Wk�����N��2X@LR�E���B-����J M��q�b����F@j0�TXʤ�c2���%�W
]��]��f�,��e��oBSƢqL͸�8����9�εơ^��Ն���r���l"���j2�{���\���˜DB�5�=�-@�p�N%&�#ʠA���'��H)%�L��&
�\q�_SV?lδq�.�42e�ʌ�C�]k-&��(�~����V4�YC���S!��(֕y�'z)4��r�_5���D0]S�i(o=zQc�1Q�O!2�a\Q� n��P�Q��B��y���{����:}��х�\����j���tG	L�3$�[������lZh��+��ҽ렑��ͩk�@���ڳ���1��Kp�hMWvƹ��Io;D�e�6�+�XKK��ڛd�o5�Z�g����(ati��C���UPA�nׄ������E��H����!r��͢�ms�l�N���R0��<��G��&a
���tg�Ik'������9ew)�|I�Q�?��Xs,�
3d��%�Oҿ�T���߰��)����?%��ꋁV�tG��%�
n�=*��b��X�ٲ*���涖CX���r�$g�5��� U���?s#�;�⎪���s`Ķ���A)�aU�V�Zz�Jh����Em>�X�Il���Ζhw B�r���B*�/i�Dt'o�ig����j�A���n���Y��sRL�)�)jSg[q�Ѱ/�e6��~0����[l�1F�F@d��
�h���,�K�!P��~�T�/`%��`�1�]��XkڮN&���������j�#J ��;Le-_�^C<&�Wkɞs$A�%#m�3�����������ڧ�F�������;s�J(���\�*�4Z����k�9�bd���&?�P�<��S�o{�ᰕ��������-��g2�e�Q�G?|Y�EY�EY�EY�EY�EY�EY�EY�E�
�BU&� �  