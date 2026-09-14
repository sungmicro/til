# 모드 A — 사전 배정기 (R 구현)
#
# 시험 **전에** 시편을 시험자에게 배정한다. base R 만 사용한다.
# Python 구현(allocate.py)과 같은 알고리즘이며, 같은 균형 조건을 만족한다.

# --- 균형 배정 ---------------------------------------------------------------

# 순서별 시료 분포가 고를수록 작아지는 점수. 0 이면 완전 균형.
order_imbalance <- function(orders, samples) {
  n_pos <- ncol(orders)
  expected <- nrow(orders) / length(samples)
  total <- 0
  for (pos in seq_len(n_pos)) {
    counts <- table(factor(orders[, pos], levels = samples))
    total <- total + sum((as.numeric(counts) - expected)^2)
  }
  total
}

# 각 시험자의 시료 수행 순서를 만든다 (순환 라틴 구성).
#
# 시험자 i, 순서 c 에 배정되는 시료는 samples[(offset_i + c) mod ns] 이다.
# 이 구성은 두 균형을 동시에, 구성 자체로 보장한다.
#   * 행: c 가 한 주기를 돌면 각 시료가 정확히 reps 번 나온다
#   * 열: 열의 시료 분포는 offset 분포와 같으므로, offset 을 고르게 나눠주면
#         모든 열이 floor(k/ns) ~ ceil(k/ns) 로 채워진다
# 무작위 재시작 탐색이나 단순 회전으로는 이 두 가지가 보장되지 않는다.
build_orders <- function(n_analysts, samples, reps) {
  ns <- length(samples)
  # sample(x) 는 x 가 길이 1 인 수치일 때 1:x 를 섞어버린다. 길이로 인덱싱해 피한다.
  shuffle <- function(x) x[sample.int(length(x))]

  labels <- shuffle(as.character(samples))
  offsets <- shuffle((seq_len(n_analysts) - 1L) %% ns)
  positions <- shuffle(seq_len(ns * reps) - 1L)

  orders <- matrix(NA_character_, nrow = n_analysts, ncol = ns * reps)
  for (i in seq_len(n_analysts)) {
    orders[i, ] <- labels[((offsets[i] + positions) %% ns) + 1L]
  }
  list(orders = orders, imbalance = order_imbalance(orders, samples))
}

#' 배정표를 만든다.
#'
#' @param analysts          시험자 목록
#' @param samples           시료 목록
#' @param reps              시험자 1인이 시료 1개당 수행할 반복수
#' @param spares_per_sample 시료당 여분 시편 수 (배정하지 않는다)
#' @param seed              난수 시드. 지정하면 배정이 재현된다
make_allocation <- function(analysts, samples, reps = 2, spares_per_sample = 0,
                            seed = NULL, prefix = "S") {
  if (reps < 1) stop("반복수는 1 이상이어야 합니다.")
  if (length(samples) < 1) stop("시료가 1개 이상이어야 합니다.")
  if (length(analysts) < 2) stop("시험자가 2명 이상이어야 합니다.")

  if (is.null(seed)) seed <- sample.int(.Machine$integer.max, 1)
  set.seed(seed)

  so <- build_orders(length(analysts), samples, reps)

  # 시료별 시편 풀을 만들고 무작위로 배정한다.
  need <- length(analysts) * reps
  pools <- lapply(samples, function(s) {
    ids <- sprintf("%s%s-%02d", prefix, s, seq_len(need + spares_per_sample))
    ids[sample.int(length(ids))]
  })
  names(pools) <- as.character(samples)

  rows <- list()
  for (ai in seq_along(analysts)) {
    for (pos in seq_len(ncol(so$orders))) {
      s <- as.character(so$orders[ai, pos])
      rows[[length(rows) + 1]] <- data.frame(
        `시험자` = analysts[ai], `순서` = pos, `시료` = s,
        `시편ID` = pools[[s]][1], check.names = FALSE, stringsAsFactors = FALSE)
      pools[[s]] <- pools[[s]][-1]
    }
  }
  rows <- do.call(rbind, rows)

  spares <- do.call(rbind, lapply(as.character(samples), function(s) {
    if (length(pools[[s]]) == 0) return(NULL)
    data.frame(`시료` = s, `시편ID` = sort(pools[[s]]),
               check.names = FALSE, stringsAsFactors = FALSE)
  }))
  if (is.null(spares)) {
    spares <- data.frame(`시료` = character(0), `시편ID` = character(0),
                         check.names = FALSE, stringsAsFactors = FALSE)
  }

  list(analysts = analysts, samples = as.character(samples), reps = reps,
       runs_per_analyst = length(samples) * reps,
       rows = rows, spares = spares, seed = seed, imbalance = so$imbalance)
}

#' 배정이 균형 조건을 만족하는지 검사한다.
check_balance <- function(alloc) {
  issues <- character(0)

  # 1. 각 시험자가 각 시료를 정확히 reps 개 받았는가
  tab <- table(alloc$rows[["시험자"]], alloc$rows[["시료"]])
  if (any(tab != alloc$reps)) {
    bad <- which(tab != alloc$reps, arr.ind = TRUE)
    for (i in seq_len(nrow(bad))) {
      issues <- c(issues, sprintf("%s 의 시료 %s 배정이 %d개 (기대 %d개)",
                                  rownames(tab)[bad[i, 1]], colnames(tab)[bad[i, 2]],
                                  tab[bad[i, 1], bad[i, 2]], alloc$reps))
    }
  }

  # 2. 시편 ID 중복 배정이 없는가
  ids <- alloc$rows[["시편ID"]]
  if (anyDuplicated(ids)) {
    issues <- c(issues, sprintf("시편 ID 중복 배정: %s",
                                paste(unique(ids[duplicated(ids)]), collapse = ", ")))
  }

  # 3. 여분이 배정과 겹치지 않는가
  ov <- intersect(alloc$spares[["시편ID"]], ids)
  if (length(ov)) {
    issues <- c(issues, sprintf("여분이 배정과 겹침: %s", paste(ov, collapse = ", ")))
  }

  # 4. 순서 균형
  order_table <- table(alloc$rows[["순서"]], alloc$rows[["시료"]])
  for (pos in seq_len(nrow(order_table))) {
    rng <- range(order_table[pos, ])
    if (diff(rng) > 1) {
      issues <- c(issues, sprintf("순서 %s 의 시료 분포 편중", rownames(order_table)[pos]))
    }
  }

  list(passed = length(issues) == 0, issues = issues, order_table = order_table,
       expected_per_cell = length(alloc$analysts) / length(alloc$samples))
}

# --- 사전 설계 검증 -----------------------------------------------------------

#' 시험 전에 이 설계로 판정이 성립하는지 몬테카를로로 계산한다.
#'
#' @param sigma_within 시험자 1인의 반복 간 표준편차 (목표 재현성, log 단위)
#' @param bias         시험자 1명에게 부여할 계통 편향 크기
#' @param sigma_pt     z-score 판정용 규정 표준편차. NULL 이면 자료에서 추정
simulate_design <- function(n_analysts, reps_total, sigma_within, bias = 0,
                            delta = 0.25, alpha = 0.05, sigma_pt = NULL,
                            trials = 2000, seed = 20260914) {
  set.seed(seed)
  counters <- c(anova_pass = 0, tost_pass = 0, z_pass = 0, levene_pass = 0)
  means <- rep(0, n_analysts)
  if (bias != 0) means[1] <- bias

  for (i in seq_len(trials)) {
    values <- unlist(lapply(means, function(m) rnorm(reps_total, m, sigma_within)))
    long <- data.frame(
      analyst = factor(rep(seq_len(n_analysts), each = reps_total)),
      value = values)

    if (levene_test(long)$p.value > alpha) counters["levene_pass"] <- counters["levene_pass"] + 1
    if (anova(lm(value ~ analyst, data = long))[["Pr(>F)"]][1] > alpha) {
      counters["anova_pass"] <- counters["anova_pass"] + 1
    }
    if (tost_all_pairs(long, delta, alpha)$passed) counters["tost_pass"] <- counters["tost_pass"] + 1

    gm <- as.numeric(tapply(long$value, long$analyst, mean))
    if (all(z_scores(gm, sigma = sigma_pt)$flag == "만족")) {
      counters["z_pass"] <- counters["z_pass"] + 1
    }
  }
  as.list(counters / trials)
}

#' 동등성 입증 확률이 target 이상이 되는 최소 반복수를 찾는다.
recommend_reps <- function(n_analysts, sigma_within, delta = 0.25, alpha = 0.05,
                           target = 0.80, max_reps = 24, trials = 1000, seed = 20260914) {
  last <- 0
  for (reps in 2:max_reps) {
    res <- simulate_design(n_analysts, reps, sigma_within, 0, delta, alpha,
                           trials = trials, seed = seed)
    last <- res$tost_pass
    if (res$tost_pass >= target) return(list(reps = reps, tost_pass = res$tost_pass, achieved = TRUE))
  }
  list(reps = NA_integer_, tost_pass = last, achieved = FALSE)
}

#' 이 설계로 입증 가능한 최소 동등성 한계를 찾는다.
#'
#' delta 는 '통과할 때까지 늘리는 값'이 아니라 적합성 목적에 따라 절차서에
#' 규정하는 값이다. 이 함수는 규정값과 달성 가능한 값의 차이를 시험 전에
#' 드러내기 위한 것이며, 둘이 벌어지면 답은 반복수를 늘리거나 기법을
#' 개선하는 것이지 delta 를 늘리는 것이 아니다.
attainable_delta <- function(n_analysts, reps_total, sigma_within, alpha = 0.05,
                             target = 0.80, trials = 600, seed = 20260914,
                             lo = 0.05, hi = 3.0, steps = 30) {
  for (i in 0:steps) {
    d <- lo + (hi - lo) * i / steps
    res <- simulate_design(n_analysts, reps_total, sigma_within, 0, d, alpha,
                           trials = trials, seed = seed)
    if (res$tost_pass >= target) {
      return(list(delta = d, tost_pass = res$tost_pass, achieved = TRUE))
    }
  }
  list(delta = NA_real_, tost_pass = 0, achieved = FALSE)
}

# --- 출력 ---------------------------------------------------------------------

#' 배정표를 CSV 로 저장한다 (배지 라벨 출력용).
write_allocation_csv <- function(alloc, path) {
  df <- alloc$rows[order(match(alloc$rows[["시험자"]], alloc$analysts),
                         alloc$rows[["순서"]]), ]
  df[["측정값"]] <- ""
  utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
  path
}

#' 측정 후 바로 분석에 넣을 수 있는 빈 결과표를 만든다.
write_results_template_csv <- function(alloc, path) {
  m <- matrix("", nrow = length(alloc$analysts), ncol = alloc$runs_per_analyst)
  df <- data.frame(`분석자` = alloc$analysts, m, check.names = FALSE,
                   stringsAsFactors = FALSE)
  colnames(df) <- c("분석자", as.character(seq_len(alloc$runs_per_analyst)))
  utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
  path
}
