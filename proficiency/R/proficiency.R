# 비교숙련도 통계 분석 — R 구현
#
# base R 만 사용한다. 추가 패키지를 설치할 수 없는 랩 PC 에서도 동작해야 한다.
# (보고서를 Word 로 내보낼 때만 rmarkdown 이 필요하다. render_report.R 참고)
#
# 같은 자료를 Python 구현(cfu_stats.py, judge.py)과 대조 검증한다.
# 두 언어가 독립적으로 같은 값을 내야 한다.

# --- 자료 읽기 ---------------------------------------------------------------

read_results <- function(path) {
  # CSV: 첫 열은 분석자명, 나머지 열은 측정값.
  raw <- utils::read.csv(path, check.names = FALSE, fileEncoding = "UTF-8-BOM",
                         stringsAsFactors = FALSE)
  names_col <- raw[[1]]
  values <- as.matrix(raw[, -1, drop = FALSE])
  storage.mode(values) <- "double"

  if (anyNA(values)) stop("측정값에 결측치가 있습니다.")
  if (ncol(values) < 2) {
    stop("분석자당 측정값이 1개뿐이면 그룹 내 변동을 추정할 수 없어 분산분석이 성립하지 않습니다.")
  }
  list(
    names = as.character(names_col),
    values = values,
    long = data.frame(
      analyst = factor(rep(as.character(names_col), times = ncol(values)),
                       levels = as.character(names_col)),
      value = as.vector(values),
      stringsAsFactors = FALSE
    )
  )
}

# R(항균활성)은 이미 log 단위다. 원 집락수만 log10 변환한다.
prepare_values <- function(values, input_type = c("r", "cfu")) {
  input_type <- match.arg(input_type)
  if (input_type == "cfu") {
    if (any(values <= 0)) stop("집락수가 0 이하이면 log 변환할 수 없습니다.")
    return(list(values = log10(values), unit = "log10(CFU)"))
  }
  list(values = values, unit = "R (항균활성, log 단위)")
}

# --- 검정 --------------------------------------------------------------------

# Levene 검정. Minitab 의 기본은 중앙값 중심(Brown-Forsythe)이다.
levene_test <- function(long, center = median) {
  z <- abs(long$value - ave(long$value, long$analyst, FUN = center))
  fit <- anova(lm(z ~ long$analyst))
  list(statistic = fit[["F value"]][1], p.value = fit[["Pr(>F)"]][1],
       df1 = fit[["Df"]][1], df2 = fit[["Df"]][2])
}

# Minitab 형식의 일원 분산분석표.
anova_table <- function(long) {
  fit <- anova(lm(value ~ analyst, data = long))
  data.frame(
    `출처` = c("요인", "오차", "총계"),
    DF = c(fit[["Df"]][1], fit[["Df"]][2], sum(fit[["Df"]])),
    `Adj SS` = c(fit[["Sum Sq"]][1], fit[["Sum Sq"]][2], sum(fit[["Sum Sq"]])),
    `Adj MS` = c(fit[["Mean Sq"]][1], fit[["Mean Sq"]][2], NA_real_),
    `F-값` = c(fit[["F value"]][1], NA_real_, NA_real_),
    `P-값` = c(fit[["Pr(>F)"]][1], NA_real_, NA_real_),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

# Grubbs 이상치 검정 (양측, 최대 편차 1개).
grubbs_test <- function(x, alpha = 0.05) {
  n <- length(x)
  if (n < 3) stop("Grubbs 검정은 3개 이상 자료가 필요합니다.")
  s <- sd(x)
  if (s == 0) {
    return(list(statistic = 0, p.value = 1, critical = NA_real_,
                index = NA_integer_, value = NA_real_, passed = TRUE))
  }
  dev <- abs(x - mean(x)) / s
  g <- max(dev)
  idx <- which.max(dev)

  a <- g^2 * n / (n - 1)^2
  p <- if (a >= 1) 0 else {
    tt <- sqrt(a * (n - 2) / (1 - a))
    min(1, 2 * n * pt(tt, n - 2, lower.tail = FALSE))
  }
  tc <- qt(1 - alpha / (2 * n), n - 2)
  gc <- ((n - 1) / sqrt(n)) * sqrt(tc^2 / (n - 2 + tc^2))

  list(statistic = g, p.value = p, critical = gc,
       index = idx, value = x[idx], passed = g <= gc)
}

# 모든 쌍의 동등성 검정(TOST). 교집합-합집합 검정이라 다중비교 보정이 필요 없다.
tost_all_pairs <- function(long, delta, alpha = 0.05) {
  fit <- anova(lm(value ~ analyst, data = long))
  mse <- fit[["Mean Sq"]][2]
  dfe <- fit[["Df"]][2]

  lv <- levels(long$analyst)
  k <- length(lv)
  rows <- list()
  for (i in seq_len(k - 1)) {
    for (j in seq(i + 1, k)) {
      a <- long$value[long$analyst == lv[i]]
      b <- long$value[long$analyst == lv[j]]
      diff <- mean(a) - mean(b)
      se <- sqrt(mse * (1 / length(a) + 1 / length(b)))
      p <- max(pt((diff + delta) / se, dfe, lower.tail = FALSE),
               pt((diff - delta) / se, dfe))
      rows[[length(rows) + 1]] <- data.frame(
        `분석자1` = lv[i], `분석자2` = lv[j], `평균차` = diff, `P-값` = p,
        check.names = FALSE, stringsAsFactors = FALSE)
    }
  }
  pairs <- do.call(rbind, rows)
  worst <- pairs[which.max(pairs[["P-값"]]), ]
  list(pairs = pairs, p.value = max(pairs[["P-값"]]),
       max_abs_diff = max(abs(pairs[["평균차"]])),
       worst = worst, delta = delta, passed = max(pairs[["P-값"]]) < alpha)
}

# ISO 13528 부속서 C, Algorithm A. 이상치를 제거하지 않고 영향만 줄인다.
algorithm_a <- function(x, max_iter = 50, tol = 1e-10) {
  p <- length(x)
  if (p < 3) stop("Algorithm A 는 3개 이상 자료가 필요합니다.")
  x_star <- median(x)
  s_star <- 1.483 * median(abs(x - x_star))

  for (i in seq_len(max_iter)) {
    if (s_star == 0) break
    d <- 1.5 * s_star
    w <- pmin(pmax(x, x_star - d), x_star + d)
    new_x <- mean(w)
    new_s <- 1.134 * sqrt(sum((w - new_x)^2) / (p - 1))
    done <- abs(new_x - x_star) < tol && abs(new_s - s_star) < tol
    x_star <- new_x; s_star <- new_s
    if (done) break
  }
  list(mean = x_star, sd = s_star)
}

# ISO/IEC 17043 z-score. 기준값과 sigma 가 없으면 Algorithm A 로 추정한다.
z_scores <- function(means, assigned = NULL, sigma = NULL) {
  est <- algorithm_a(means)
  if (is.null(assigned)) assigned <- est$mean
  if (is.null(sigma)) sigma <- est$sd

  z <- if (sigma == 0) rep(NA_real_, length(means)) else (means - assigned) / sigma
  flag <- ifelse(is.na(z), "판정불가",
          ifelse(abs(z) < 2, "만족", ifelse(abs(z) < 3, "경고", "부적합")))
  list(assigned = assigned, sigma = sigma, z = z, flag = flag,
       estimated = is.null(assigned) || is.null(sigma))
}

# 현행 판정 기준(등분산 + ANOVA)을 통과하는지.
passes_classic <- function(long, alpha = 0.05) {
  levene_test(long)$p.value > alpha && anova(lm(value ~ analyst, data = long))[["Pr(>F)"]][1] > alpha
}

# 전체 값을 무작위로 재배정했을 때의 통과율.
# 통과율이 높은데 실제 배정만 탈락한다면, 우연이 아니라 체계적 편향이 실재한다는 뜻이다.
random_reallocation_rate <- function(long, trials = 10000, seed = 20260914, alpha = 0.05) {
  set.seed(seed)
  pool <- long$value
  g <- long$analyst
  hit <- 0L
  for (i in seq_len(trials)) {
    shuffled <- data.frame(analyst = g, value = sample(pool))
    if (passes_classic(shuffled, alpha)) hit <- hit + 1L
  }
  hit / trials
}

# --- 통합 ---------------------------------------------------------------------

analyze_proficiency <- function(data, input_type = "r", delta = 0.25,
                                alpha = 0.05, trials = 10000,
                                assigned = NULL, sigma = NULL) {
  prep <- prepare_values(data$values, input_type)
  long <- data.frame(
    analyst = factor(rep(data$names, times = ncol(prep$values)), levels = data$names),
    value = as.vector(prep$values), stringsAsFactors = FALSE)

  means <- tapply(long$value, long$analyst, mean)
  sds <- tapply(long$value, long$analyst, sd)
  flat <- long$value

  gr_all <- grubbs_test(flat, alpha)
  list(
    names = data$names, unit = prep$unit, input_type = input_type,
    alpha = alpha, delta = delta, n_per_analyst = ncol(prep$values),
    long = long,
    summary = data.frame(`분석자` = data$names, N = ncol(prep$values),
                         `평균` = as.numeric(means), `표준편차` = as.numeric(sds),
                         check.names = FALSE, stringsAsFactors = FALSE),
    levene = levene_test(long),
    anova = anova_table(long),
    anova_p = anova(lm(value ~ analyst, data = long))[["Pr(>F)"]][1],
    tost = tost_all_pairs(long, delta, alpha),
    grubbs_all = gr_all,
    grubbs_all_owner = data$names[((gr_all$index - 1) %% length(data$names)) + 1],
    grubbs_means = grubbs_test(as.numeric(means), alpha),
    z = z_scores(as.numeric(means), assigned, sigma),
    classic_pass = passes_classic(long, alpha),
    random_rate = random_reallocation_rate(long, trials, alpha = alpha)
  )
}
