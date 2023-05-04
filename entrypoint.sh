#!/bin/bash -le

# verify
if [[ ! "${GITHUB_BASE_REF}" ]]; then
  echo "ERROR: This action is only for pull-request events."
  exit 1
fi
if [[ ! "${INPUT_BOTEMAIL}" ]]; then
  echo "ERROR: Please set inputs.botEmail"
  exit 1
fi
if [[ "${INPUT_ENABLEREVIEWCOMMENT}" = "true" && ! "${INPUT_BOTGITHUBTOKEN}" ]]; then
  echo "ERROR: Please set inputs.botGithubToken"
  exit 1
fi

# generate
git config --global --add safe.directory ${GITHUB_WORKSPACE}
cd ${GITHUB_WORKSPACE}
echo "INFO: git fetch"
git fetch
SRC_FILES=$(git diff origin/${GITHUB_BASE_REF} --name-only | grep ".puml" || :)
echo "INFO: source files: " + ${SRC_FILES}
for SRC_FILE in ${SRC_FILES}; do
  java -jar /plantuml.jar $SRC_FILE -charset UTF-8
  echo "generate from $SRC_FILE"
done

# commit
if [[ ! $(git status --porcelain) ]]; then
  exit 0
fi
git config user.name "${GITHUB_ACTOR}"
git config user.email "${INPUT_BOTEMAIL}"
git checkout ${GITHUB_HEAD_REF}
git add .
git status
echo "INFO: git commit"
git commit -m "add generated diagrams"
echo "INFO: git push"
git push origin HEAD:${GITHUB_HEAD_REF}
echo "comitted png files"

# add review comment
if [[ "${INPUT_ENABLEREVIEWCOMMENT}" != "true" ]]; then
  echo "Not adding comment"
  exit 0
fi
echo "git fetch"
git fetch
echo "calculate GITHUB_SHA_AFTER"
GITHUB_SHA_AFTER=$(git rev-parse origin/${GITHUB_HEAD_REF})
echo "calculate diffs"
echo "GITHUB_SHA: ${GITHUB_SHA}"
echo "RELEVANT_SHA: ${RELEVANT_SHA}"
echo "GITHUB_SHA_AFTER: ${GITHUB_SHA_AFTER}"
DIFF_FILES=`git diff ${RELEVANT_SHA} ${GITHUB_SHA_AFTER} --name-only | grep ".png"`
echo $DIFF_FILES
BODY="## Diagrams changed\n"
for DIFF_FILE in ${DIFF_FILES}; do
  TEMP=`cat << EOS
### [${DIFF_FILE}](https://github.com/${GITHUB_REPOSITORY}/blob/${GITHUB_SHA_AFTER}/${DIFF_FILE})\n
<details><summary>Before</summary>\n
\n
![before](https://github.com/${GITHUB_REPOSITORY}/blob/${RELEVANT_SHA}/${DIFF_FILE}?raw=true)\n
\n
</details>\n
\n
![after](https://github.com/${GITHUB_REPOSITORY}/blob/${GITHUB_SHA_AFTER}/${DIFF_FILE}?raw=true)\n
\n
EOS
  `
  BODY=${BODY}${TEMP}
done
BODY=`echo ${BODY} | sed -e "s/\:/\\\:/g"`
PULL_NUM=`echo ${GITHUB_REF} | sed -r "s/refs\/pull\/([0-9]+)\/merge/\1/"`
echo "body: ${BODY}"
echo "pull-num: ${PULL_NUM}"
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token ${INPUT_BOTGITHUBTOKEN}" \
  -d "{\"event\": \"COMMENT\", \"body\": \"${BODY}\"}" \
  "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/pulls/${PULL_NUM}/reviews"
echo "added review comments"
