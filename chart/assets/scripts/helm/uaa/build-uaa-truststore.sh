#!/usr/bin/env bash

find_keytool_or_fail_fast() {
  local has_keytool
  ls "${JAVA_HOME}"/bin/keytool
  has_keytool=$?
  if [ ${has_keytool} -ne 0 ]; then
    exit ${has_keytool}
  fi
}
import_cert() {
  local pemfile="${1}"
  local alias="${2}"
  echo "Adding ${pemfile} to truststore"
  # Have to use cat instead of -file
  # because keytool won't understand all of the filenames!
  cat "${pemfile}" | "${JAVA_HOME}"/bin/keytool \
    -noprompt \
    -import \
    -trustcacerts \
    -alias "${alias}" \
    -keystore "${TRUSTSTORE_FILE}" \
    -storepass "${TRUSTSTORE_PASSWORD}"
}
get_alias() {
  local pemfile="${1}"
  basename "${pemfile}" .pem
}
add_ca_certs() {
  local has_ca_certs
  ls ${SECRETS_DIR}/ca_certs/*.pem
  has_ca_certs=$?
  if [ ${has_ca_certs} -eq 0 ]; then
    for cert in ${SECRETS_DIR}/ca_certs/*.pem; do
      import_cert "${cert}" "$(get_alias $cert)"
    done
  fi
}
add_system_certs() {
  for cert in $OS_CERTS_DIR/*.pem; do
    import_cert "${cert}" "$(get_alias $cert)"
  done
}
main() {
  find_keytool_or_fail_fast
  add_ca_certs
  add_system_certs
}
main
