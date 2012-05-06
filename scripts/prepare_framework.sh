set -e

mkdir -p "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Versions/${FRAMEWORK_VERSION}/Headers"

# Link the "Current" version to "${FRAMEWORK_VERSION}"
ln -sfh ${FRAMEWORK_VERSION} "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Versions/Current"
ln -sfh Versions/Current/Headers "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Headers"
ln -sfh "Versions/Current/${PRODUCT_NAME}" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/${PRODUCT_NAME}"

# The -a ensures that the headers maintain the source modification date so that we don't constantly
# cause propagating rebuilds of files that import these headers.
cp -a "${BUILT_PRODUCTS_DIR}/${PUBLIC_HEADERS_FOLDER_PATH}/" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Versions/${FRAMEWORK_VERSION}/Headers"
