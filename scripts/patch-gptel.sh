# 1. Remove the header line logic from after-preset
sed -i '' -e '910,912d' lisp/gptel-config.el

# 2. Replace nucleus--effective-preset
sed -i '' 's/(eq (and (fboundp '"'"'nucleus--effective-preset) *(nucleus--effective-preset))/(eq (and (boundp '"'"'gptel--preset) gptel--preset)/g' lisp/gptel-config.el
sed -i '' 's/(let\* ((preset (and (fboundp '"'"'nucleus--effective-preset) (nucleus--effective-preset)))/(let* ((preset (and (boundp '"'"'gptel--preset) gptel--preset))/g' lisp/gptel-config.el

# 3. Replace nucleus--project-root
sed -i '' 's/(if (fboundp '"'"'nucleus--project-root) (nucleus--project-root) default-directory)/(if-let ((proj (and (featurep '"'"'project) (project-current nil)))) (project-root proj) default-directory)/g' lisp/gptel-config.el

# 4. Rename nucleus-resolve-model
sed -i '' 's/nucleus-resolve-model/my\/gptel-resolve-model/g' lisp/gptel-config.el

# 5. Rename nucleus-tools to my/gptel-tools
sed -i '' 's/nucleus-tools-readonly/my\/gptel-tools-readonly/g' lisp/gptel-config.el
sed -i '' 's/nucleus-tools-action/my\/gptel-tools-action/g' lisp/gptel-config.el
