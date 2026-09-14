#!/usr/bin/env Rscript
# 비교숙련도 보고서를 Word(.docx)로 렌더링한다.
#
#   Rscript render_report.R --csv ../samples/antibacterial_R_saureus.csv \
#       --strain "황색포도상구균 (Staphylococcus aureus)" --atcc ATCC6538P --lot 8923 \
#       --out ../out/saureus.docx
#
# --sigma 를 주면 절차서에 규정된 목표 재현성으로 z-score 를 계산한다.
# 주지 않으면 참가자 자료에서 ISO 13528 Algorithm A 로 추정한다.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  i <- match(paste0("--", key), args)
  if (is.na(i) || i == length(args)) default else args[[i + 1]]
}
num_arg <- function(key, default) {
  v <- get_arg(key)
  if (is.null(v)) default else as.numeric(v)
}

csv <- get_arg("csv")
if (is.null(csv)) stop("--csv 가 필요합니다.")
out <- get_arg("out", sub("\\.csv$", ".docx", basename(csv)))
out <- normalizePath(out, mustWork = FALSE)
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)

sigma <- get_arg("sigma")
assigned <- get_arg("assigned")

rmarkdown::render(
  input = "report.Rmd",
  output_format = "word_document",
  output_file = out,
  params = list(
    csv = normalizePath(csv),
    strain = get_arg("strain", "(균주 미지정)"),
    atcc = get_arg("atcc", "-"),
    lot = get_arg("lot", "-"),
    method = get_arg("method", "ISO 22196"),
    input_type = get_arg("type", "r"),
    delta = num_arg("delta", 0.25),
    alpha = num_arg("alpha", 0.05),
    trials = num_arg("trials", 10000),
    assigned = if (is.null(assigned)) NULL else as.numeric(assigned),
    sigma = if (is.null(sigma)) NULL else as.numeric(sigma)
  ),
  # Rmd 를 별도 환경에서 실행한다. 기본값(parent.frame)이면 Rmd 안의 변수가
  # 이 스크립트의 변수를 덮어쓴다.
  envir = new.env(parent = globalenv()),
  quiet = TRUE
)
cat("보고서를 저장했습니다:", out, "\n")
